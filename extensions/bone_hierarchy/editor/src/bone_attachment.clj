(ns editor.bone-attachment
  (:require [clojure.data.json :as json]
            [clojure.string :as string]
            [dynamo.graph :as g]
            [editor.build-target :as bt]
            [editor.collection :as collection]
            [editor.defold-project :as project]
            [editor.fxui :as fxui]
            [editor.geom :as geom]
            [editor.graph-util :as gu]
            [editor.pose :as pose]
            [editor.properties-view :as properties-view]
            [editor.resource :as resource]
            [editor.resource-node :as resource-node]
            [editor.workspace :as workspace]))

(defn- fail [text] (throw (ex-info text {})))
(defn- message [error]
  (.getMessage ^Throwable (loop [e error] (if-let [cause (.getCause ^Throwable e)] (recur cause) e))))
(defn- instance-pose [data]
  (pose/make (or (:position data) [0.0 0.0 0.0])
             (or (:rotation data) [0.0 0.0 0.0 1.0])
             (or (:scale3 data) (vec (repeat 3 (double (or (:scale data) 1.0)))))))

;; Merge collection-instance overrides by component and property ID.
(defn- merge-properties [base overrides]
  (reduce (fn [items override]
            (if-let [index (first (keep-indexed #(when (= (:id %2) (:id override)) %1) items))]
              (assoc items index (if (:properties override)
                                  (update (items index) :properties merge-properties (:properties override))
                                  override))
              (conj items override)))
          (vec base) overrides))

(defn attachment-plan [raw owner-id taken-ids]
  (when (empty? raw) (fail "Source collection contains no game objects."))
  (let [names (into {} (map (fn [{:keys [key]}] [key (str owner-id "/" key)]) raw))]
    ;; Keep the source collection paths, including nested collection names.
    ;; GO parent relationships are applied separately and never enter this path.
    (when-not (= (count raw) (count names))
      (fail "Source contains duplicate game object paths after expanding nested collections."))
    (when-let [collision (first (filter (set taken-ids) (vals names)))]
      (fail (str "Game object '" collision "' already exists. Undo/delete the previous attachment or use a different owner GO.")))
    (mapv (fn [item] (assoc item :id (names (:key item)) :parent (names (:parent-key item)))) raw)))

(defn collection-plan [project source destination owner-id taken-ids]
  (let [load-opts (project/make-load-opts project)
        resolve-resource (:resolve-resource-fn load-opts)
        destination-path (resource/proj-path destination)]
    (letfn [(expand [source namespace root-pose inherited seen]
              (let [path (resource/proj-path source)]
                (when (= path destination-path) (fail "Source includes the destination collection. Choose a separate template."))
                (when (contains? seen path) (fail (str "Collection cycle at " path)))
                (when-not (resource/exists? source) (fail (str "Missing collection: " path)))
                (let [node (project/get-resource-node project path)
                      data (when node (g/node-value node :save-value))]
                  (when (or (nil? data) (g/error-value? data)) (fail (str "Cannot read collection: " path)))
                  (let [instances (vec (concat (map #(assoc % :kind :reference) (:instances data))
                                               (map #(assoc % :kind :embedded) (:embedded-instances data))))
                        all-ids (map :id (concat instances (:collection-instances data)))
                        _ (when-not (= (count all-ids) (count (set all-ids))) (fail (str "Duplicate IDs in " path)))
                        by-id (into {} (map (juxt :id identity) instances))
                        parents (reduce (fn [parents instance]
                                          (reduce (fn [parents child]
                                                    (when-not (by-id child) (fail (str "Missing child '" child "' in " path)))
                                                    (when (contains? parents child) (fail (str "Multiple parents for '" child "'.")))
                                                    (assoc parents child (:id instance))) parents (:children instance))) {} instances)
                        depth (fn [id]
                                (loop [id id seen #{} n 0]
                                  (when (seen id) (fail (str "GO hierarchy cycle in " path)))
                                  (if-let [parent (parents id)] (recur parent (conj seen id) (inc n)) n)))
                        ordered (sort-by #(depth (:id %)) instances)
                        qualify #(str namespace %)
                        local (mapv (fn [instance]
                                      (let [id (:id instance) parent (parents id)
                                            prototype (when (= :reference (:kind instance))
                                                        (resolve-resource source (:prototype instance)))
                                            _ (when (and prototype (not (resource/exists? prototype)))
                                                (fail (str "Missing prototype: " (resource/proj-path prototype))))]
                                        {:key (qualify id) :parent-key (when parent (qualify parent))
                                         :owner-resource source :kind (:kind instance) :prototype prototype :data (:data instance)
                                         :properties (merge-properties (:component-properties instance) (get inherited id))
                                         :pose (cond-> (instance-pose instance) (nil? parent) (pose/pre-multiply root-pose))})) ordered)
                        nested (mapcat
                                 (fn [instance]
                                   (let [child-prefix (str (:id instance) "/")
                                         inherited-child (into {} (keep (fn [[id props]]
                                                                         (when (string/starts-with? id child-prefix)
                                                                           [(subs id (count child-prefix)) props])) inherited))
                                         own (into {} (map (juxt :id :properties) (:instance-properties instance)))
                                         overrides (merge-with merge-properties own inherited-child)]
                                     (expand (resolve-resource source (:collection instance))
                                             (qualify child-prefix)
                                             (pose/pre-multiply (instance-pose instance) root-pose)
                                             overrides (conj seen path)))) (:collection-instances data))]
                    (into local nested)))))]
      (attachment-plan (expand source "" pose/default {} #{}) owner-id taken-ids))))

(defn- plan->tx [project coll parent plan]
  (let [nodes (atom {}) load-opts (project/make-load-opts project)]
    (vec (mapcat
           (fn [{:keys [id pose kind prototype data properties owner-resource] parent-id :parent}]
             (let [parent-node (if parent-id (@nodes parent-id) parent)
                   _ (when-not parent-node (fail (str "Missing parent for " id)))
                   transform {:position (:translation pose) :rotation (:rotation pose) :scale3 (:scale pose)}
                   remember (fn [[node]] (swap! nodes assoc id node) nil)]
               (if (= :reference kind)
                 (vec (#'collection/make-ref-go coll prototype id transform parent-node properties remember))
                 (let [data (update data :components
                                   (fn [components]
                                     (mapv (fn [component]
                                             (if-let [override (first (filter #(= (:id %) (:id component)) properties))]
                                               (update component :properties merge-properties (:properties override)) component)) components)))]
                   (vec (#'collection/make-embedded-go coll load-opts owner-resource data id transform parent-node remember)))))) plan))))

(defn attach! [{:keys [project] :as context} node-id]
  (try
    (let [source (g/node-value node-id :source)
          _ (when-not source (fail "Choose a Source collection."))
          ;; Editor plugins are load-string'd independently; resolve the shared
          ;; owner lookup after all plugins have loaded, regardless of file order.
          target ((ns-resolve 'editor.bone-hierarchy 'target-context) context node-id)
          _ (when-not target (fail "Open the .collection and select BoneAttachment inside its game object. A standalone .go cannot store child game objects."))
          {:keys [collection parent component]} target
          component-pose (if component (g/node-value component :pose) pose/default)
          plan (collection-plan project source (resource-node/owner-resource collection) (g/node-value parent :id)
                                (concat (g/node-value collection :ids)
                                        (keys (g/node-value collection :go-inst-ids))))
          plan (mapv #(if (:parent %) % (update % :pose pose/pre-multiply component-pose)) plan)]
      (g/transact
        (concat (g/operation-label "Attach BoneAttachment")
                (plan->tx project collection parent plan)
                (g/set-property node-id :result (str "Attached " (count plan) " game objects under " (g/node-value parent :id) ". Save the collection. Undo is available.")))))
    (catch Throwable e (g/transact (g/set-property node-id :result (str "Error: " (message e)))))))

(defmethod properties-view/make-control-view ::attach [property context _]
  {:fx/type fxui/button :text "Attach" :max-width Double/MAX_VALUE
   :disable (or (not= 1 (count (:node-ids property))) (not (first (:values property))))
   :on-action (fn [_] (attach! context (first (:node-ids property))))})

(defn- build-marker [resource _ _]
  {:resource resource :content
   (clojure.lang.Reflector/invokeStaticMethod
     ^Class (workspace/load-class! "com.dynamo.bob.pipeline.BoneAttachmentBuilder") "marker" (object-array 0))})

(g/defnode BoneAttachmentNode
  (inherits resource-node/ResourceNode)
  (property source resource/Resource
    (value (gu/passthrough source-resource))
    (set (fn [ctx self old new] (project/resource-setter ctx self old new [:resource :source-resource])))
    (dynamic read-only? (g/fnk [_node-id] (g/override? (g/now) _node-id)))
    (dynamic edit-type (g/constantly {:type resource/Resource :ext "collection"})))
  ;; Retain old serialized settings so loading the updated plugin does not
  ;; rewrite unrelated embedded components. Naming no longer uses this value.
  (property id-prefix g/Str (default "") (dynamic visible (g/constantly false)))
  (property status g/Str
    (value (g/fnk [source] (if source "Attach uses owner GO ID/source GO ID. Existing IDs are never overwritten." "Choose a .collection template.")))
    (dynamic read-only? (g/constantly true)))
  (property result g/Str (default "") (dynamic read-only? (g/constantly true)))
  (property attach g/Bool
    (value (g/fnk [source] (boolean source)))
    (dynamic label (g/constantly "")) (dynamic edit-type (g/constantly {:type ::attach})))
  (display-order [:source :status :result :attach])
  (input source-resource resource/Resource)
  (output scene g/Any (g/fnk [_node-id] {:node-id _node-id :aabb geom/empty-bounding-box :children []}))
  (output save-value g/Any :cached (g/fnk [source id-prefix] {:source (or (resource/resource->proj-path source) "") :id-prefix id-prefix}))
  (output build-targets g/Any :cached
    (g/fnk [_node-id resource]
      [(bt/with-content-hash {:node-id _node-id :resource (workspace/make-build-resource resource)
                             :build-fn build-marker :user-data {}})])))

(defn- load-attachment [{:keys [resolve-resource-fn]} {:keys [node-id source-value owner-resource]}]
  [(g/set-property node-id :source (when (seq (:source source-value)) (resolve-resource-fn owner-resource (:source source-value))))
   (g/set-property node-id :id-prefix (or (:id-prefix source-value) ""))])

(fn [workspace]
  (g/transact
    (workspace/register-resource-type workspace
      :ext "boneattachment" :build-ext "scriptc" :label "BoneAttachment" :node-type BoneAttachmentNode
      :textual? true :language "json"
      :read-fn (fn [_ _ readable] (json/read-str (slurp readable) :key-fn keyword))
      :write-fn (fn [value] (str (json/write-str value) "\n")) :load-fn load-attachment
      :dependencies-fn (fn [{:keys [resolve-proj-path-fn]} owner data]
                         (if (seq (:source data)) [(resolve-proj-path-fn owner (:source data))] []))
      :icon "icons/32/Icons_22-Model.png" :category "Components" :view-types [:scene :text]
      :tags #{:component :overridable-properties}
      :tag-opts {:component {:transform-properties #{:position :rotation}}}
      :template "/extensions/bone_hierarchy/editor/resources/templates/template.boneattachment")))
