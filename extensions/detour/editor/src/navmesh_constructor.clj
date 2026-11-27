(ns editor.detour-navmesh-constructor
  (:require [clojure.data.json :as json]
            [clojure.string :as string]
            [dynamo.graph :as g]
            [editor.build-target :as bt]
            [editor.defold-project :as project]
            [editor.fxui :as fxui]
            [editor.geom :as geom]
            [editor.gl :as gl]
            [editor.gl.pass :as pass]
            [editor.gl.vertex2 :as vtx]
            [editor.graph-util :as gu]
            [editor.graphics.types :as graphics.types]
            [editor.math :as math]
            [editor.pose :as pose]
            [editor.properties-view :as properties-view]
            [editor.resource :as resource]
            [editor.resource-node :as resource-node]
            [editor.scene :as scene]
            [editor.scene-picking :as picking]
            [editor.shaders :as shaders]
            [editor.types :as types]
            [editor.workspace :as workspace])
  (:import [com.jogamp.opengl GL2]
           [javax.vecmath Matrix4d Point3d]
           [editor.types AABB]))

(def ^:private constructor-class (delay (workspace/load-class! "com.defold.navmesh.NavMeshConstructor")))
(def ^:private shader shaders/basic-color-straight-alpha-local-space)
(defn- call [method & args]
  (clojure.lang.Reflector/invokeStaticMethod ^Class @constructor-class method (to-array args)))
(defn- message [error]
  (.getMessage ^Throwable (loop [e error] (if-let [cause (.getCause ^Throwable e)] (recur cause) e))))
(defn- read-config [_ _ readable] (json/read-str (slurp readable) :key-fn keyword))
(defn- write-config [value] (str (json/write-str value) "\n"))

;; Read the same selected model scene that Defold displays, including its node
;; poses. This supports .model -> .gltf/.glb, named mesh selection and external
;; buffers without a second importer. Baking uses static/rest geometry.
(defn- scene-geometry [model-scene]
  (let [positions (java.util.ArrayList.) indices (java.util.ArrayList.)]
    (letfn [(visit [s ^Matrix4d parent]
              (let [transform (Matrix4d. parent)
                    _ (when-let [p (:pose s)] (.mul transform ^Matrix4d (pose/matrix p)))
                    buffers (get-in s [:renderable :user-data :mesh-renderable-buffers])
                    position-buffer (first (get-in buffers [:attribute-buffers :semantic-type-position]))]
                (when position-buffer
                  (let [data (into [] (graphics.types/buffer-data position-buffer))
                        base (quot (.size positions) 3)
                        vertex-count (quot (count data) 4)
                        index-buffer (:index-buffer buffers)
                        local-indices (if index-buffer
                                        (mapv #(bit-and (long %) (if (instance? Short %) 0xffff 0xffffffff))
                                              (into [] (graphics.types/buffer-data index-buffer)))
                                        (vec (range vertex-count)))]
                    (when (or (> (+ base vertex-count) 2000000) (> (+ (.size indices) (count local-indices)) 6000000))
                      (throw (IllegalArgumentException. "Model exceeds two million vertices or triangles")))
                    (when-not (zero? (rem (count local-indices) 3))
                      (throw (IllegalArgumentException. "Model geometry must contain complete triangles")))
                    (doseq [[x y z _] (partition 4 data)]
                      (let [p (Point3d. (double x) (double y) (double z))]
                        (.transform transform p)
                        (.add positions (float (.x p))) (.add positions (float (.y p))) (.add positions (float (.z p)))))
                    (doseq [[a b c] (partition 3 local-indices)
                            i (if (neg? (.determinant transform)) [a c b] [a b c])]
                      (when-not (< -1 i vertex-count) (throw (IllegalArgumentException. "Model index is out of bounds")))
                      (.add indices (int (+ base i))))))
                (doseq [child (:children s)] (visit child transform))))]
      (visit model-scene (doto (Matrix4d.) (.setIdentity)))
      {:positions (float-array positions) :indices (int-array indices)})))

(g/defnk produce-geometry [source ^:try source-scene]
  (cond
    (nil? source) {:error "Choose a .model in Source."}
    (g/error-value? source-scene) {:error "The source model has errors. Open it to check its mesh and materials."}
    :else (try (scene-geometry source-scene) (catch Throwable e {:error (message e)}))))

(g/defnk produce-bake-config [cell-size cell-height tile-size border-size max-slope walkable-height walkable-climb walkable-radius max-edge-length max-simplification-error min-region-size merge-region-size max-vertices-per-poly detail-sample-distance detail-sample-max-error]
  [cell-size cell-height tile-size border-size max-slope walkable-height walkable-climb walkable-radius max-edge-length max-simplification-error min-region-size merge-region-size max-vertices-per-poly detail-sample-distance detail-sample-max-error])

(g/defnk produce-preview [geometry bake-config preview-mode]
  (if (:error geometry) geometry
    (try
      (into {} (map (fn [[k v]] [(keyword k) v]))
            (call "preview" (:positions geometry) (:indices geometry) (double-array bake-config) (int preview-mode)))
      (catch Throwable e {:error (message e)}))))

(defn- make-buffer [^floats vertices tint opacity offset]
  (when (and vertices (pos? (alength vertices)))
    (let [buffer (vtx/make-vertex-buffer (shaders/vertex-description shader) :static (quot (alength vertices) 7))
          bytes (vtx/buf buffer) floats (.asFloatBuffer bytes)]
      (doseq [i (range 0 (alength vertices) 7)]
        (.put floats (aget vertices i)) (.put floats (float (+ offset (aget vertices (+ i 1)))))
        (.put floats (aget vertices (+ i 2)))
        (doseq [j (range 4)]
          (.put floats (float (* (if tint (nth tint j) (aget vertices (+ i 3 j))) (if (= j 3) opacity 1))))))
      (.position bytes (* 4 (.position floats)))
      (vtx/flip! buffer))))

(g/defnk produce-draw-data [preview color surface-opacity height-offset preview-mode]
  (when-not (:error preview)
    {:surface (make-buffer (:triangles preview) (when (= 1 preview-mode) color) surface-opacity height-offset)
     :edges (make-buffer (:lines preview) (when (= 1 preview-mode) color) 1 height-offset)}))

(defn- draw-buffer [^GL2 gl args shader id buffer primitive]
  (when (and buffer (pos? (count buffer)))
    (let [binding (vtx/use-with id buffer shader)]
      (gl/with-gl-bindings gl args [shader binding]
        (gl/gl-draw-arrays gl primitive 0 (count buffer))))))

(defn- render-preview [^GL2 gl args renderables _]
  (doseq [r renderables]
    (let [{:keys [surface edges show-surface show-edges x-ray]} (:user-data r)
          id (:node-id r)
          args (merge args (math/derive-render-transforms (:world-transform r) (:view args) (:projection args) (:texture args)))]
      (if (= pass/selection (:pass args))
        (when show-surface
          (draw-buffer gl (assoc args :id-color (picking/renderable-picking-id-uniform r))
                       shaders/selection-uniform-local-space [id ::selection] surface GL2/GL_TRIANGLES))
        (try
          (when x-ray (.glDisable gl GL2/GL_DEPTH_TEST))
          (when show-surface (draw-buffer gl args shader [id ::surface] surface GL2/GL_TRIANGLES))
          (when show-edges (draw-buffer gl args shader [id ::edges] edges GL2/GL_LINES))
          (finally (when x-ray (.glEnable gl GL2/GL_DEPTH_TEST))))))))

(g/defnk produce-aabb [^:try source-scene]
  (or (when-not (g/error-value? source-scene) (:aabb source-scene)) geom/empty-bounding-box))
(g/defnk produce-scene [_node-id aabb ^:try source-scene draw-data show-source show-surface show-edges x-ray]
  {:node-id _node-id :aabb aabb
   :renderable {:render-fn render-preview :tags #{:model} :select-batch-key _node-id
                :passes [pass/transparent pass/selection]
                :user-data (assoc draw-data :show-surface show-surface :show-edges show-edges :x-ray x-ray)}
   :children (if (and show-source source-scene (not (g/error-value? source-scene)))
               [(scene/claim-scene source-scene _node-id "constructor-source")] [])})

(g/defnk produce-save-value [source output cell-size cell-height tile-size border-size max-slope walkable-height walkable-climb walkable-radius max-edge-length max-simplification-error min-region-size merge-region-size max-vertices-per-poly detail-sample-distance detail-sample-max-error preview-mode show-source show-surface show-edges color surface-opacity height-offset x-ray]
  {:source (or (resource/resource->proj-path source) "") :output output
   :cell-size cell-size :cell-height cell-height :tile-size tile-size :border-size border-size :max-slope max-slope :walkable-height walkable-height :walkable-climb walkable-climb :walkable-radius walkable-radius :max-edge-length max-edge-length :max-simplification-error max-simplification-error :min-region-size min-region-size :merge-region-size merge-region-size :max-vertices-per-poly max-vertices-per-poly :detail-sample-distance detail-sample-distance :detail-sample-max-error detail-sample-max-error :preview-mode preview-mode :show-source show-source :show-surface show-surface :show-edges show-edges :color color :surface-opacity surface-opacity :height-offset height-offset :x-ray x-ray})

(defn- build-constructor [resource _ _] {:resource resource :content (call "marker")})
(g/defnk produce-build-targets [_node-id resource]
  [(bt/with-content-hash {:node-id _node-id :resource (workspace/make-build-resource resource)
                        :build-fn build-constructor :user-data {}})])

(g/defnode NavMeshConstructorNode
  (inherits resource-node/ResourceNode)
  (property source resource/Resource
    (value (gu/passthrough source-resource))
    (set (fn [ctx self old new]
           (project/resource-setter ctx self old new [:resource :source-resource] [:scene :source-scene])))
    (dynamic edit-type (g/constantly {:type resource/Resource :ext "model"}))
    (dynamic error (g/fnk [_node-id geometry]
                     (when-let [text (:error geometry)] (g/error-warning _node-id :source text)))))
  (property output g/Str (default "")
    (dynamic tooltip (g/constantly "Project path /.../mesh.bin. Empty saves beside a .navmeshconstructor resource. For an inline component, specify Output. Replaced only when you press Bake.")))
  (property cell-size g/Num (default 0.2)
    (dynamic tooltip (g/constantly "Voxel width and depth in model units.")))
  (property cell-height g/Num (default 0.2)
    (dynamic tooltip (g/constantly "Voxel height in model units.")))
  (property tile-size g/Int (default 0)
    (dynamic tooltip (g/constantly "0 builds one mesh; 8..1024 builds tiles of this width in cells.")))
  (property border-size g/Int (default 0)
    (dynamic tooltip (g/constantly "Border in cells. Tiled builds use at least Walkable Radius + 3.")))
  (property max-slope g/Num (default 60)
    (dynamic tooltip (g/constantly "Maximum walkable slope in degrees, less than 90.")))
  (property walkable-height g/Int (default 3)
    (dynamic tooltip (g/constantly "Required clearance in vertical cells, 3..255. World height = value * Cell Height.")))
  (property walkable-climb g/Int (default 2)
    (dynamic tooltip (g/constantly "Maximum step in vertical cells. World step = value * Cell Height.")))
  (property walkable-radius g/Int (default 1)
    (dynamic tooltip (g/constantly "Obstacle clearance in horizontal cells. World radius = value * Cell Size.")))
  (property max-edge-length g/Int (default 12)
    (dynamic tooltip (g/constantly "Maximum contour edge length in horizontal cells. 0 disables the limit.")))
  (property max-simplification-error g/Num (default 1.3)
    (dynamic tooltip (g/constantly "Maximum contour simplification error in cells.")))
  (property min-region-size g/Int (default 8)
    (dynamic tooltip (g/constantly "Minimum region size. Regions smaller than this value squared in cells are removed.")))
  (property merge-region-size g/Int (default 20)
    (dynamic tooltip (g/constantly "Merge small regions below this value squared in cells.")))
  (property max-vertices-per-poly g/Int (default 6)
    (dynamic tooltip (g/constantly "Maximum vertices per polygon, 3..6.")))
  (property detail-sample-distance g/Num (default 6)
    (dynamic tooltip (g/constantly "Detail sampling distance multiplied by Cell Size; below 0.9 disables sampling.")))
  (property detail-sample-max-error g/Num (default 1)
    (dynamic tooltip (g/constantly "Detail height error multiplied by Cell Height.")))
  (property preview-mode g/Int (default 1)
    (dynamic edit-type (g/constantly {:type :choicebox :options
      [[1 "NavMesh"] [2 "BV Tree"] [3 "Solid Heightfield"] [4 "Walkable Heightfield"]
       [5 "Compact Heightfield"] [6 "Regions"] [7 "Distance Field"] [8 "Raw Contours"]
       [9 "Contours"] [10 "Polygon Mesh"] [11 "Detail Mesh"]]})))
  (property show-source g/Bool (default true))
  (property show-surface g/Bool (default true))
  (property show-edges g/Bool (default true))
  (property color types/Color (default [0.0 0.75 0.95 1.0]))
  (property surface-opacity g/Num (default 0.35))
  (property height-offset g/Num (default 0.03))
  (property x-ray g/Bool (default false))
  (property last-saved g/Str (default "") (dynamic read-only? (g/constantly true)))
  (property status g/Str
    (value (g/fnk [preview] (or (:error preview) (:warning preview) "Preview ready. Bake writes the .bin file.")))
    (dynamic read-only? (g/constantly true)))
  (property bake g/Bool
    (value (g/fnk [preview] (boolean (:bytes preview))))
    (dynamic label (g/constantly ""))
    (dynamic edit-type (g/constantly {:type ::bake})))
  (display-order [:source :output :cell-size :cell-height :tile-size :border-size :max-slope :walkable-height :walkable-climb :walkable-radius :max-edge-length :max-simplification-error :min-region-size :merge-region-size :max-vertices-per-poly :detail-sample-distance :detail-sample-max-error :preview-mode :show-source :show-surface :show-edges
                  :color :surface-opacity :height-offset :x-ray :last-saved :status :bake])
  (input source-resource resource/Resource)
  (input source-scene g/Any)
  (output geometry g/Any :cached produce-geometry)
  (output bake-config g/Any :cached produce-bake-config)
  (output preview g/Any :cached produce-preview)
  (output draw-data g/Any :cached produce-draw-data)
  (output aabb AABB :cached produce-aabb)
  (output scene g/Any :cached produce-scene)
  (output save-value g/Any :cached produce-save-value)
  (output build-targets g/Any :cached produce-build-targets))

(defn- bake! [workspace node-id]
  (try
    (let [preview (g/node-value node-id :preview)
          output (g/node-value node-id :output)
          output (if (string/blank? output)
                   (if-let [path (resource/proj-path (g/node-value node-id :resource))]
                     (string/replace path #"\.navmeshconstructor$" ".bin")
                     (throw (IllegalArgumentException. "Set Output to /path/mesh.bin for an inline component.")))
                   output)]
      (when-let [error (:error preview)] (throw (IllegalArgumentException. error)))
      (call "saveBin" (str (g/node-value workspace :root)) output (:bytes preview))
      (g/transact (g/set-property node-id :last-saved (str output " (" (alength ^bytes (:bytes preview)) " bytes)")))
      (workspace/resource-sync! workspace))
    (catch Throwable e
      (g/transact (g/set-property node-id :last-saved (str "Error: " (message e)))))))

;; Extend only this plugin's property type; the standard inspector owns layout,
;; selection and the native scene viewport. There is no separate editor window.
(defmethod properties-view/make-control-view ::bake [property {:keys [workspace]} _]
  {:fx/type fxui/button :text "Запечь" :max-width Double/MAX_VALUE
   :disable (or (not= 1 (count (:node-ids property))) (not (first (:values property))))
   :on-action (fn [_] (bake! workspace (first (:node-ids property))))})

(defn- load-constructor [{:keys [resolve-resource-fn]} {:keys [node-id source-value owner-resource]}]
  (into [(g/set-property node-id :source (when (seq (:source source-value))
                                         (resolve-resource-fn owner-resource (:source source-value))))]
        (for [key [:output :cell-size :cell-height :tile-size :border-size :max-slope :walkable-height :walkable-climb :walkable-radius :max-edge-length :max-simplification-error :min-region-size :merge-region-size :max-vertices-per-poly :detail-sample-distance :detail-sample-max-error :preview-mode :show-source :show-surface :show-edges
                   :color :surface-opacity :height-offset :x-ray]
              :when (contains? source-value key)]
          (g/set-property node-id key (get source-value key)))))

(fn [workspace]
  (g/transact
    (workspace/register-resource-type workspace
      :ext "navmeshconstructor" :build-ext "scriptc" :label "NavMeshConstructor" :node-type NavMeshConstructorNode
      :textual? true :language "json" :read-fn read-config :write-fn write-config :load-fn load-constructor
      :dependencies-fn (fn [{:keys [resolve-proj-path-fn]} owner data]
                         (if (seq (:source data)) [(resolve-proj-path-fn owner (:source data))] []))
      :icon "icons/32/Icons_22-Model.png" :category "Components" :view-types [:scene :text] :tags #{:component}
      :tag-opts {:component {:transform-properties #{:position :rotation}}}
      :template "/extensions/detour/editor/resources/templates/template.navmeshconstructor")))
