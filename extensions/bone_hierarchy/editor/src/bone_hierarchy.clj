(ns editor.bone-hierarchy
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.string :as string]
            [dynamo.graph :as g]
            [editor.build-target :as bt]
            [editor.collection :as collection]
            [editor.core :as core]
            [editor.defold-project :as project]
            [editor.fxui :as fxui]
            [editor.game-object :as game-object]
            [editor.geom :as geom]
            [editor.graph-util :as gu]
            [editor.id :as id]
            [editor.pose :as pose]
            [editor.properties-view :as properties-view]
            [editor.resource :as resource]
            [editor.resource-node :as resource-node]
            [editor.workspace :as workspace])
  (:import [java.nio ByteBuffer ByteOrder]
           [javax.vecmath Matrix4d]))

(defn- message [error]
  (.getMessage ^Throwable (loop [e error] (if-let [cause (.getCause ^Throwable e)] (recur cause) e))))
(defn- read-config [_ _ readable] (json/read-str (slurp readable) :key-fn keyword))
(defn- write-config [value] (str (json/write-str value) "\n"))

(defn- valid-id [s fallback]
  (let [s (string/replace (or s "") #"[/#:\s\\]" "_")]
    (if (string/blank? s) fallback s)))

;; Read all skins. Defold's model importer can select just the first skin and
;; rename its root, which would lose bones in multi-armature GLBs.
(defn read-glb-json [source]
  (with-open [stream (io/input-stream source)]
    (let [header (.readNBytes stream 20)]
      (when-not (= 20 (alength header)) (throw (ex-info "Truncated GLB header." {})))
      (let [buffer (doto (ByteBuffer/wrap header) (.order ByteOrder/LITTLE_ENDIAN))
            magic (.getInt buffer) version (.getInt buffer)
            total (Integer/toUnsignedLong (.getInt buffer))
            length (Integer/toUnsignedLong (.getInt buffer)) kind (.getInt buffer)]
        (when-not (and (= magic 0x46546c67) (= version 2) (= kind 0x4e4f534a)
                       (<= 2 length 67108864) (<= (+ 20 length) total))
          (throw (ex-info "Expected a valid GLB 2.0 JSON chunk (at most 64 MiB)." {})))
        (let [bytes (.readNBytes stream (int length))]
          (when-not (= length (alength bytes)) (throw (ex-info "Truncated GLB JSON chunk." {})))
          (json/read-str (String. bytes java.nio.charset.StandardCharsets/UTF_8) :key-fn keyword))))))

(defn- checked-vector [values defaults label]
  (let [values (or values defaults)]
    (when-not (and (= (count defaults) (count values))
                   (every? #(and (number? %) (Double/isFinite (double %))) values))
      (throw (ex-info (str "Invalid node " label ".") {})))
    (mapv double values)))

(defn- node-matrix [node]
  (if-let [values (:matrix node)]
    (doto (Matrix4d. (double-array (checked-vector values (repeat 16 0.0) "matrix"))) (.transpose))
    (let [rotation (checked-vector (:rotation node) [0 0 0 1] "rotation")
          length (Math/sqrt (reduce + (map #(* % %) rotation)))]
      (when (< length 1.0e-12) (throw (ex-info "Node has a zero quaternion." {})))
      (pose/matrix (pose/make (checked-vector (:translation node) [0 0 0] "translation")
                              (mapv #(/ % length) rotation)
                              (checked-vector (:scale node) [1 1 1] "scale"))))))

(defn- matrix-pose [^Matrix4d matrix]
  (let [p (pose/from-matrix matrix)
        rebuilt (pose/matrix p)]
    (when-not (.epsilonEquals matrix ^Matrix4d rebuilt 1.0e-5)
      (throw (ex-info "Bone transform contains shear or a singular scale that a Defold GO cannot represent. Apply the armature transforms before exporting." {})))
    p))

(defn gltf-skeleton [data]
  (let [nodes (vec (:nodes data))
        n (count nodes)
        valid-index? #(and (integer? %) (<= 0 %) (< % n))
        parents (reduce-kv
                  (fn [parents index node]
                    (reduce (fn [parents child]
                              (when-not (valid-index? child) (throw (ex-info "Invalid GLB child index." {:child child})))
                              (when (contains? parents child) (throw (ex-info "GLB node has multiple parents." {:child child})))
                              (assoc parents child index)) parents (:children node))) {} nodes)
        joints (set (mapcat :joints (:skins data)))
        _ (doseq [joint joints]
            (when-not (valid-index? joint) (throw (ex-info "Invalid GLB joint index." {:joint joint}))))
        ;; Walking every parent chain also rejects cycles before creating anything.
        ancestors (into {} (for [i (range n)]
                             [i (loop [p (parents i) seen #{i} result []]
                                  (if (nil? p) result
                                    (do (when (seen p) (throw (ex-info "Cycle in GLB hierarchy." {:node i})))
                                        (recur (parents p) (conj seen p) (conj result p)))))]))
        ordered (sort-by #(vector (count (ancestors %)) %) joints)
        indices (zipmap ordered (range))]
    {:bones
     (mapv (fn [i]
             (let [ancestor-joint (first (filter joints (ancestors i)))
                   chain (cons i (take-while #(not= ancestor-joint %) (ancestors i)))
                   matrix (doto (Matrix4d.) (.setIdentity))]
               (doseq [index (reverse chain)] (.mul matrix ^Matrix4d (node-matrix (nodes index))))
               (let [p (matrix-pose matrix)
                     transform {:translation (:translation p) :rotation (:rotation p) :scale (:scale p)}]
                 {:name (or (:name (nodes i)) (str "bone_" i))
                  :parent (if ancestor-joint (indices ancestor-joint) -1)
                  :local transform :world transform}))) ordered)}))

(g/defnk produce-skeleton [source ^:try source-sha256]
  (cond
    (nil? source) {:error "Choose the .glb used by your model."}
    (g/error-value? source-sha256) {:error "Source does not exist or cannot be read."}
    :else (try (gltf-skeleton (read-glb-json source))
               (catch Throwable e {:error (message e)}))))

;; Root transforms include non-joint ancestors (e.g. Blender's Armature).
;; Child transforms are relative to their nearest parent joint.
(defn skeleton-plan [skeleton prefix taken-ids]
  (let [bones (vec (:bones skeleton))
        ;; Preserve path separators already present in the owning GO's ID.
        prefix (if (string/blank? prefix) "" (str (string/replace prefix #"[#:\s\\]" "_") "/"))]
    (when (empty? bones)
      (throw (ex-info "Source has no skeleton. Export an armature/skin to the GLB." {})))
    (let [used (atom #{})
          names (mapv (fn [i bone]
                        (let [name (id/gen (str prefix (valid-id (:name bone) (str "bone_" i))) @used)]
                          (swap! used conj name) name))
                      (range) bones)]
      (when-let [collision (first (filter (set taken-ids) names))]
        (throw (ex-info (str "Game object '" collision "' already exists. Undo/delete the previous bones or change Id Prefix.") {})))
      (vec (map-indexed
              (fn [i bone]
                (let [parent (:parent bone)
                      root? (or (nil? parent) (= -1 parent) (= 4294967295 parent))
                      _ (when-not (or root? (and (integer? parent) (<= 0 parent) (< parent i)))
                          (throw (ex-info "Invalid skeleton: parents must precede children." {:bone i :parent parent})))
                      transform (if root? (:world bone) (:local bone))
                      {:keys [translation rotation scale]} transform]
                  (when-not (and (= 3 (count translation)) (= 4 (count rotation)) (= 3 (count scale))
                                 (every? #(and (number? %) (Double/isFinite (double %)))
                                         (concat translation rotation scale)))
                    (throw (ex-info "Invalid bone transform." {:bone i})))
                  {:id (names i) :parent (when-not root? (names parent))
                   :pose (pose/make translation rotation scale)}))
              bones)))))

(defn- pose->pb [p]
  {:position (:translation p) :rotation (:rotation p) :scale3 (:scale p)})

(defn- ownership-chain [node-id]
  (take-while some? (iterate core/owner-node-id node-id)))

(defn- outline-target [coll node-id selected-node-ids]
  (when (and coll (g/node-instance? collection/CollectionNode coll))
    (let [basis (g/now)
          matches? (fn [n] (and n (= (g/override-root basis n) (g/override-root basis node-id))))]
      (letfn [(visit [outline parent]
                (let [n (:node-id outline)
                      parent (if (g/node-instance? collection/GameObjectInstanceNode n) n parent)]
                  (if (and parent (g/node-instance? game-object/ComponentNode n)
                           (matches? (get-in outline [:alt-outline :node-id])))
                    [{:collection coll :parent parent :component n
                      :resource-node (get-in outline [:alt-outline :node-id])}]
                    (mapcat #(visit % parent) (:children outline)))))]
        (let [candidates (vec (visit (g/node-value coll :node-outline) nil))
              selected (filterv #(contains? (set selected-node-ids) (:component %)) candidates)
              exact (filterv #(= node-id (:resource-node %)) candidates)]
          (cond
            (= 1 (count selected)) (first selected)
            (= 1 (count exact)) (first exact)
            (= 1 (count candidates)) (first candidates)
            (seq candidates) (throw (ex-info "Select exactly one authoring component inside the target game object." {}))))))))

(defn- target-context [{:keys [app-view active-collection selected-node-ids]} node-id]
  (let [active-collection (or active-collection (when app-view (g/node-value app-view :active-resource-node)))
        selected-target (outline-target active-collection node-id (or selected-node-ids (when app-view (g/node-value app-view :selected-node-ids))))
        chain (ownership-chain node-id)
        component (first (filter #(g/node-instance? game-object/ComponentNode %) chain))
        parent (first (filter #(g/node-instance? collection/GameObjectInstanceNode %) chain))
        coll (first (filter #(g/node-instance? collection/CollectionNode %) chain))
        target (or selected-target (when (and parent coll) {:collection coll :parent parent :component component}))]
    (when target
      (when (or (g/override? (g/now) (:collection target)) (g/override? (g/now) (:parent target)))
        (throw (ex-info "Open the original collection to create child game objects." {})))
      target)))

;; All graph steps are committed together, including parent links and status.
;; No files are overwritten and the user's unsaved collection stays in memory.
(defn- plan->tx [project coll parent owner-resource plan]
  (let [node-ids (atom {})
        load-opts (project/make-load-opts project)]
    (vec
      (mapcat
        (fn [{:keys [id pose] bone-parent :parent}]
          (let [parent-node (if bone-parent (@node-ids bone-parent) parent)]
            (when-not parent-node (throw (ex-info "Missing bone parent." {:id id})))
            (vec (#'collection/make-embedded-go coll load-opts owner-resource {} id
                    (pose->pb pose) parent-node
                    (fn [[new-id]] (swap! node-ids assoc id new-id) nil)))))
        plan))))

(g/defnk produce-status [source ^:try source-skeleton]
  (cond
    (nil? source) "Choose the same .glb used by your model's Skeleton."
    (g/error-value? source-skeleton) "Source could not be imported. Check the GLB for errors."
    (:error source-skeleton) (:error source-skeleton)
    (empty? (:bones source-skeleton)) "Source has no skeleton. Export an armature/skin to the GLB."
    :else (str (count (:bones source-skeleton)) " bones ready. Create makes editable game objects in the rest pose.")))

(g/defnk produce-save-value [source id-prefix]
  {:source (or (resource/resource->proj-path source) "") :id-prefix id-prefix})

(defn- build-marker [resource _ _]
  {:resource resource :content
   (clojure.lang.Reflector/invokeStaticMethod
     ^Class (workspace/load-class! "com.dynamo.bob.pipeline.BoneHierarchyBuilder") "marker" (object-array 0))})

(g/defnk produce-build-targets [_node-id resource]
  [(bt/with-content-hash {:node-id _node-id :resource (workspace/make-build-resource resource)
                        :build-fn build-marker :user-data {}})])

(g/defnode BoneHierarchyNode
  (inherits resource-node/ResourceNode)
  (property source resource/Resource
    (value (gu/passthrough source-resource))
    (set (fn [ctx self old new]
           (project/resource-setter ctx self old new [:resource :source-resource] [:sha256 :source-sha256])))
    (dynamic read-only? (g/fnk [_node-id] (g/override? (g/now) _node-id)))
    (dynamic edit-type (g/constantly {:type resource/Resource :ext "glb"})))
  (property id-prefix g/Str (default "")
    (dynamic read-only? (g/fnk [_node-id] (g/override? (g/now) _node-id)))
    (dynamic tooltip (g/constantly "Bone IDs use prefix/bone_name. Empty uses the owning GO's ID, preserving its path. Configure Source and Id Prefix in the original .go when using referenced game objects.")))
  (property status g/Str (value produce-status) (dynamic read-only? (g/constantly true)))
  (property result g/Str (default "") (dynamic read-only? (g/constantly true)))
  (property create g/Bool
    (value (g/fnk [^:try source-skeleton] (and (not (g/error-value? source-skeleton)) (boolean (seq (:bones source-skeleton))))))
    (dynamic label (g/constantly ""))
    (dynamic edit-type (g/constantly {:type ::create})))
  (display-order [:source :id-prefix :status :result :create])
  (input source-resource resource/Resource)
  (input source-sha256 g/Any)
  (output source-skeleton g/Any :cached produce-skeleton)
  (output scene g/Any (g/fnk [_node-id] {:node-id _node-id :aabb geom/empty-bounding-box :children []}))
  (output save-value g/Any :cached produce-save-value)
  (output build-targets g/Any :cached produce-build-targets))

(defn create! [{:keys [project] :as context} node-id]
  (try
    (let [skeleton (g/node-value node-id :source-skeleton)
          _ (when (g/error-value? skeleton) (throw (ex-info "Cannot import Source." {})))
          _ (when-let [error (:error skeleton)] (throw (ex-info error {})))
          target (target-context context node-id)
          _ (when-not target
              (throw (ex-info "Open the .collection and select BoneHierarchy inside its game object. A standalone .go cannot store child game objects." {})))
          {:keys [collection parent component]} target
          component-pose (if component (g/node-value component :pose) pose/default)
          prefix (g/node-value node-id :id-prefix)
          prefix (if (string/blank? prefix) (g/node-value parent :id) prefix)
          plan (skeleton-plan skeleton prefix (concat (g/node-value collection :ids)
                                                     (keys (g/node-value collection :go-inst-ids))))
          plan (mapv #(if (:parent %) % (update % :pose pose/pre-multiply component-pose)) plan)]
      (g/transact
        (concat (g/operation-label "Create BoneHierarchy")
                (plan->tx project collection parent (resource-node/owner-resource collection) plan)
                (g/set-property node-id :result (str "Created " (count plan) " bones under " (g/node-value parent :id) ". Save the collection. Undo is available.")))))
    (catch Throwable e
      (g/transact (g/set-property node-id :result (str "Error: " (message e)))))))

(defmethod properties-view/make-control-view ::create [property context _]
  {:fx/type fxui/button :text "Create" :max-width Double/MAX_VALUE
   :disable (or (not= 1 (count (:node-ids property))) (not (first (:values property))))
   :on-action (fn [_] (create! context (first (:node-ids property))))})

(defn- load-hierarchy [{:keys [resolve-resource-fn]} {:keys [node-id source-value owner-resource]}]
  (into [(g/set-property node-id :source (when (seq (:source source-value))
                                         (resolve-resource-fn owner-resource (:source source-value))))]
        (for [key [:id-prefix] :when (contains? source-value key)]
          (g/set-property node-id key (get source-value key)))))

(fn [workspace]
  (g/transact
    (workspace/register-resource-type workspace
      :ext "bonehierarchy" :build-ext "scriptc" :label "BoneHierarchy" :node-type BoneHierarchyNode
      :textual? true :language "json" :read-fn read-config :write-fn write-config :load-fn load-hierarchy
      :dependencies-fn (fn [{:keys [resolve-proj-path-fn]} owner data]
                         (if (seq (:source data)) [(resolve-proj-path-fn owner (:source data))] []))
      ;; Give each referenced GO its own component identity. Without this tag
      ;; Defold shares embedded component nodes across instances of a .go.
      :icon "icons/32/Icons_22-Model.png" :category "Components" :view-types [:scene :text] :tags #{:component :overridable-properties}
      :tag-opts {:component {:transform-properties #{:position :rotation}}}
      :template "/extensions/bone_hierarchy/editor/resources/templates/template.bonehierarchy")))
