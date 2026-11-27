;; Project-local NavMesh editor integration for Defold 1.14.
;; The native geometry adapter calls the unchanged upstream duDebugDrawNavMesh.
(ns editor.detour-navmesh
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [dynamo.graph :as g]
            [editor.build-target :as bt]
            [editor.defold-project :as project]
            [editor.geom :as geom]
            [editor.gl :as gl]
            [editor.gl.pass :as pass]
            [editor.gl.vertex2 :as vtx]
            [editor.graph-util :as gu]
            [editor.math :as math]
            [editor.resource :as resource]
            [editor.resource-node :as resource-node]
            [editor.scene-picking :as picking]
            [editor.shaders :as shaders]
            [editor.types :as types]
            [editor.workspace :as workspace])
  (:import [com.jogamp.opengl GL2]
           [javax.vecmath Point3d]
           [editor.types AABB]))

(def ^:private defaults
  {:source "" :color [0.0 0.75 0.95 1.0] :show-surface true :show-edges true
   :surface-opacity 0.22 :height-offset 0.03 :x-ray false})
(def ^:private preview-class (delay (workspace/load-class! "com.defold.navmesh.NavMeshPreview")))
(def ^:private resource-class (delay (workspace/load-class! "com.defold.navmesh.NavMeshResource")))
(def ^:private color-shader shaders/basic-color-straight-alpha-local-space)

(defn- read-config [_opts _owner readable]
  (merge defaults (json/read-str (slurp readable) :key-fn keyword)))
(defn- write-config [value] (str (json/write-str value) "\n"))

(g/defnk produce-geometry [source source-sha256]
  ;; Connecting sha256 makes an external .bin edit invalidate the cached geometry.
  (if (nil? source)
    {:error "Choose a RecastDemo navmesh.bin in Source."}
    (try
      (with-open [stream (io/input-stream source)]
        (let [arrays (clojure.lang.Reflector/invokeStaticMethod
                       ^Class @preview-class "read" (to-array [(.readAllBytes stream)]))]
          {:triangles (mapv vec (partition 3 (aget arrays 0)))
           :lines (mapv vec (partition 3 (aget arrays 1)))}))
      (catch Throwable error
        (let [cause (loop [e error] (if-let [c (.getCause e)] (recur c) e))]
          {:error (str "NavMesh: " (.getMessage cause))})))))

(defn- make-buffer [positions color]
  (let [vb (vtx/make-vertex-buffer (shaders/vertex-description color-shader) :static (count positions))
        bytes (vtx/buf vb)
        floats (.asFloatBuffer bytes)
        rgba (float-array color)]
    (doseq [position positions]
      (.put floats (float-array position))
      (.put floats rgba))
    (.position bytes (* 4 (.position floats)))
    (vtx/flip! vb)))

(g/defnk produce-draw-data [geometry color surface-opacity height-offset]
  (when-not (:error geometry)
    (let [raise (fn [points] (mapv (fn [[x y z]] [x (+ y height-offset) z]) points))
          triangles (raise (:triangles geometry))
          lines (raise (:lines geometry))]
      {:surface (make-buffer triangles (assoc color 3 (* (nth color 3) surface-opacity)))
       :edges (make-buffer lines color)})))

(defn- draw-buffer [^GL2 gl args shader request-id vb primitive]
  (when (and vb (pos? (count vb)))
    (let [binding (vtx/use-with request-id vb shader)]
      (gl/with-gl-bindings gl args [shader binding]
        (gl/gl-draw-arrays gl primitive 0 (count vb))))))

(defn- render-navmesh [^GL2 gl args renderables _count]
  (doseq [renderable renderables]
    (let [{:keys [surface edges show-surface show-edges x-ray]} (:user-data renderable)
          node-id (:node-id renderable)
          selection? (= pass/selection (:pass args))
          args (merge args (math/derive-render-transforms (:world-transform renderable)
                             (:view args) (:projection args) (:texture args)))]
      (if selection?
        (when (or show-surface show-edges)
          (draw-buffer gl (assoc args :id-color (picking/renderable-picking-id-uniform renderable))
            shaders/selection-uniform-local-space [node-id ::selection] surface GL2/GL_TRIANGLES))
        (try
          (when x-ray (.glDisable gl GL2/GL_DEPTH_TEST))
          (when show-surface
            (draw-buffer gl args color-shader [node-id ::surface] surface GL2/GL_TRIANGLES))
          (when show-edges
            (draw-buffer gl args color-shader [node-id ::edges] edges GL2/GL_LINES))
          (finally
            (when x-ray (.glEnable gl GL2/GL_DEPTH_TEST))))))))

(g/defnk produce-aabb [geometry height-offset]
  (let [points (:triangles geometry)]
    (if (seq points)
      (let [[lx ly lz] (reduce (partial mapv min) points)
            [hx hy hz] (reduce (partial mapv max) points)]
        (types/->AABB (Point3d. lx (+ ly height-offset) lz)
                     (Point3d. hx (+ hy height-offset) hz)))
      geom/empty-bounding-box)))

(g/defnk produce-scene [_node-id aabb draw-data show-surface show-edges x-ray]
  {:node-id _node-id :aabb aabb
   :renderable {:render-fn render-navmesh :tags #{:model}
                :select-batch-key _node-id
                :user-data (assoc draw-data :show-surface show-surface :show-edges show-edges :x-ray x-ray)
                :passes [pass/transparent pass/selection]}})

(g/defnk produce-save-value [source color show-surface show-edges surface-opacity height-offset x-ray]
  {:source (or (resource/resource->proj-path source) "") :color color
   :show-surface show-surface :show-edges show-edges :surface-opacity surface-opacity
   :height-offset height-offset :x-ray x-ray})

(g/defnk produce-errors [_node-id geometry surface-opacity height-offset color]
  (when-let [message (or (:error geometry)
                        (when-not (<= 0 surface-opacity 1) "Surface Opacity must be between 0 and 1.")
                        (when-not (Double/isFinite (double height-offset)) "Height Offset must be finite.")
                        (when-not (and (= 4 (count color)) (every? #(<= 0 % 1) color))
                          "Color must contain four values between 0 and 1."))]
    (g/error-fatal _node-id :source message)))

(defn- build-navmesh [resource deps {:keys [config source material xray-material]}]
  (with-open [stream (io/input-stream source)]
    {:resource resource
     :content (clojure.lang.Reflector/invokeStaticMethod
                ^Class @resource-class "compile"
                (to-array [(.getBytes (json/write-str config) "UTF-8") (.readAllBytes stream)
                           (resource/proj-path (get deps material))
                           (resource/proj-path (get deps xray-material))]))}))

(g/defnk produce-build-targets [_node-id resource own-build-errors source-sha256 source save-value
                              material-build-targets xray-material-build-targets]
  (g/precluding-errors own-build-errors
    [(bt/with-content-hash {:node-id _node-id :resource (workspace/make-build-resource resource)
                            :deps (concat material-build-targets xray-material-build-targets)
                            :build-fn build-navmesh
                            :user-data {:config save-value :source source :source-sha256 source-sha256
                                        :material (:resource (first material-build-targets))
                                        :xray-material (:resource (first xray-material-build-targets))}})]))

(g/defnode NavMeshNode
  (inherits resource-node/ResourceNode)
  (property source resource/Resource
    (value (gu/passthrough source-resource))
    (set (fn [ctx self old new]
           (project/resource-setter ctx self old new
             [:resource :source-resource] [:sha256 :source-sha256])))
    (dynamic edit-type (g/constantly {:type resource/Resource :ext "bin"}))
    (dynamic error (g/fnk [_node-id geometry]
                     (when-let [message (:error geometry)] (g/error-fatal _node-id :source message)))))
  (property color types/Color (default (:color defaults)))
  (property show-surface g/Bool (default true))
  (property show-edges g/Bool (default true))
  (property surface-opacity g/Num (default 0.22))
  (property height-offset g/Num (default 0.03))
  (property x-ray g/Bool (default false))
  (property material resource/Resource
    (value (gu/passthrough material-resource))
    (set (fn [ctx self old new]
           (project/resource-setter ctx self old new
             [:resource :material-resource] [:build-targets :material-build-targets])))
    (dynamic visible (g/constantly false)))
  (property xray-material resource/Resource
    (value (gu/passthrough xray-material-resource))
    (set (fn [ctx self old new]
           (project/resource-setter ctx self old new
             [:resource :xray-material-resource] [:build-targets :xray-material-build-targets])))
    (dynamic visible (g/constantly false)))
  (input source-resource resource/Resource)
  (input source-sha256 g/Str)
  (input material-resource resource/Resource)
  (input material-build-targets g/Any)
  (input xray-material-resource resource/Resource)
  (input xray-material-build-targets g/Any)
  (output geometry g/Any :cached produce-geometry)
  (output draw-data g/Any :cached produce-draw-data)
  (output aabb AABB :cached produce-aabb)
  (output scene g/Any :cached produce-scene)
  (output save-value g/Any :cached produce-save-value)
  (output own-build-errors g/Any produce-errors)
  (output build-targets g/Any :cached produce-build-targets))

(defn- load-navmesh [{:keys [resolve-resource-fn]} {:keys [node-id source-value owner-resource]}]
  (concat
    [(g/set-property node-id :material (resolve-resource-fn owner-resource "/detour/resources/navmesh.material"))
     (g/set-property node-id :xray-material (resolve-resource-fn owner-resource "/detour/resources/navmesh_xray.material"))
     (g/set-property node-id :source (when (seq (:source source-value))
                                     (resolve-resource-fn owner-resource (:source source-value))))]
    (for [key [:color :show-surface :show-edges :surface-opacity :height-offset :x-ray]]
      (g/set-property node-id key (get source-value key (get defaults key))))))

(fn [workspace]
  (g/transact
    (workspace/register-resource-type workspace
      :ext "navmesh" :build-ext "navmeshc" :label "NavMesh" :node-type NavMeshNode
      :textual? true :language "json" :read-fn read-config :write-fn write-config
      :load-fn load-navmesh
      :dependencies-fn (fn [{:keys [resolve-proj-path-fn]} owner data]
                         (if (seq (:source data)) [(resolve-proj-path-fn owner (:source data))] []))
      :icon "icons/32/Icons_22-Model.png" :category "Components"
      :view-types [:scene :text] :tags #{:component}
      :tag-opts {:component {:transform-properties #{:position :rotation}}}
      :template "/detour/editor/resources/templates/template.navmesh")))
