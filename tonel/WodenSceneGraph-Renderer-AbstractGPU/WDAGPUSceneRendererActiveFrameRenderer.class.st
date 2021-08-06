"
I am renderer for a specific frame.
I hold references to resources that are still in flight on the GPU that cannot be garbage collected until my job is finished.
"
Class {
	#name : #WDAGPUSceneRendererActiveFrameRenderer,
	#superclass : #WDFrameRenderer,
	#instVars : [
		'renderer',
		'stateTracker',
		'activeResources',
		'activeSlabResource',
		'commandQueue',
		'activeResourceDictionary',
		'currentObjectVertexBinding',
		'currentObjectPrimitiveTopology'
	],
	#classVars : [
		'PrimitiveTopologyMap'
	],
	#pools : [
		'AGPUConstants'
	],
	#category : #'WodenSceneGraph-Renderer-AbstractGPU-Renderer'
}

{ #category : #initialization }
WDAGPUSceneRendererActiveFrameRenderer class >> initialize [
	PrimitiveTopologyMap := Dictionary newFromPairs: { 
		WDPrimitiveTopologyPoints uniqueInstance . AGPU_POINTS.
		WDPrimitiveTopologyLines uniqueInstance . AGPU_LINES.
		WDPrimitiveTopologyLineStrip uniqueInstance . AGPU_LINE_STRIP.
		WDPrimitiveTopologyTriangles uniqueInstance . AGPU_TRIANGLES.
		WDPrimitiveTopologyTriangleStrip uniqueInstance . AGPU_TRIANGLE_STRIP.
	}.
]

{ #category : #rendering }
WDAGPUSceneRendererActiveFrameRenderer >> abortRecording [
	self freeActiveResources.
	stateTracker := nil.
]

{ #category : #rendering }
WDAGPUSceneRendererActiveFrameRenderer >> activateMaterial: material withVertexBinding: vertexBinding primitiveTopology: primitiveTopology [
	| validMaterial vertexBindingHandle |
	validMaterial := material ifNil: [ renderer resourceCache defaultMaterial ].
	
	vertexBindingHandle := self validVertexBindingFor: vertexBinding.
	stateTracker
		setVertexLayout: vertexBindingHandle first;
		useVertexBinding: vertexBindingHandle second;
		setPrimitiveType: (PrimitiveTopologyMap at: primitiveTopology).
	currentObjectVertexBinding := vertexBinding.
	currentObjectPrimitiveTopology := primitiveTopology.

	^ validMaterial emitActivationCommandsOn: self

]

{ #category : #rendering }
WDAGPUSceneRendererActiveFrameRenderer >> beginRecordingCommandsOn: aStateTracker queue: aCommandQueue [
	stateTracker := aStateTracker.
	commandQueue := aCommandQueue.
	activeResources := OrderedCollection new.
	activeSlabResource := OrderedCollection new.
	activeResourceDictionary := Dictionary new.
	stateTracker beginRecordingCommands.
	self resetCurrentActiveState.
]

{ #category : #rendering }
WDAGPUSceneRendererActiveFrameRenderer >> bindCameraState: cameraState [
	stateTracker useShaderResources: (activeResourceDictionary at: cameraState ifAbsentPut: [ 
		| binding |
		binding := renderer resourceCache rendererShaderSignature allocateCameraState.
		binding writeState: cameraState with: WDAGPUCameraStateUniformBufferWriter.
		activeSlabResource add: binding.
		binding
	]) bindingHandle.

]

{ #category : #rendering }
WDAGPUSceneRendererActiveFrameRenderer >> bindLightingState: lightingState [
	stateTracker useShaderResources: (activeResourceDictionary at: lightingState ifAbsentPut: [ 
		| binding |
		binding := renderer resourceCache rendererShaderSignature allocateLightingState.
		binding writeState: lightingState with: WDAGPULightingStateUniformBufferWriter.
		activeSlabResource add: binding.
		binding
	]) bindingHandle.

]

{ #category : #rendering }
WDAGPUSceneRendererActiveFrameRenderer >> bindObjectState: objectState [
	stateTracker useShaderResources: (activeResourceDictionary at: objectState ifAbsentPut: [ 
		| binding |
		binding := renderer resourceCache rendererShaderSignature allocateObjectState.
		binding writeState: objectState with: WDAGPUObjectStateUniformBufferWriter.
		activeSlabResource add: binding.
		binding
	]) bindingHandle.

]

{ #category : #rendering }
WDAGPUSceneRendererActiveFrameRenderer >> convertedCameraState: aCameraState [
	^ aCameraState shallowCopy
		projectionMatrix: renderer resourceCache projectionNDCAdjustMatrix * aCameraState projectionMatrix;
		yourself
]

{ #category : #rendering }
WDAGPUSceneRendererActiveFrameRenderer >> emitMetallicRoughnessMaterialActivationCommands: material [
	| locationMask |
	locationMask := currentObjectVertexBinding locationMask.
	
	stateTracker
		useShaderResources: (activeResourceDictionary at: material ifAbsentPut: [ 
			| binding |
			binding := renderer resourceCache rendererShaderSignature allocateMaterialState.
			binding
				writeState: material with: WDAGPUMetallicRoughnessMaterialUniformBufferWriter;
				bindSampledTextureView: (self validTextureViewHandleFor: material baseColorTexture fallbackTextureWith: [renderer resourceCache whiteTexture2D]) inSlot: 1;
				bindSampledTextureView: (self validTextureViewHandleFor: material emissiveTexture fallbackTextureWith: [renderer resourceCache transparentTexture2D]) inSlot: 2;
				bindSampledTextureView: (self validTextureViewHandleFor: material normalTexture fallbackTextureWith: [renderer resourceCache neutralNormalTexture]) inSlot: 3;
				bindSampledTextureView: (self validTextureViewHandleFor: material occlusionTexture fallbackTextureWith: [renderer resourceCache whiteTexture2D]) inSlot: 4;
				bindSampledTextureView: (self validTextureViewHandleFor: material metallicRoughnessTexture fallbackTextureWith: [renderer resourceCache whiteTexture2D]) inSlot: 5.
			activeSlabResource add: binding.
			binding
		]) bindingHandle;
		setVertexStage: (renderer resourceCache genericSurfaceMaterialVertexShaderWithLocationMask: currentObjectVertexBinding locationMask) entryPoint: 'main';
		setFragmentStage: renderer resourceCache forwardMetallicRoughnessFragmentShader entryPoint: 'main'.
	^ true
]

{ #category : #rendering }
WDAGPUSceneRendererActiveFrameRenderer >> emitRenderingCommandsForMeshPrimitive: meshPrimitive [
	(self activateMaterial: meshPrimitive material withVertexBinding: meshPrimitive vertexBinding primitiveTopology: meshPrimitive topology) ifFalse: [ ^ self ].
		
	meshPrimitive indices ifNil: [
		stateTracker
			drawArrays: meshPrimitive vertexBinding vertexCount instance_count: 1 first_vertex: 0 base_instance: 0
	] ifNotNil: [ :indicesAccessor |
		stateTracker
			useIndexBufferAt: (self validBufferHandleForAccessor: indicesAccessor)
				offset: indicesAccessor byteOffset + indicesAccessor bufferView byteOffset
				index_size: indicesAccessor componentType size;
			drawElements: indicesAccessor count instance_count: 1 first_index: 0 base_vertex: 0 base_instance: 0
	].

]

{ #category : #rendering }
WDAGPUSceneRendererActiveFrameRenderer >> emitUnlitMaterialActivationCommands: material [
	| locationMask |
	locationMask := currentObjectVertexBinding locationMask.
	
	stateTracker
		useShaderResources: (activeResourceDictionary at: material ifAbsentPut: [ 
			| binding |
			binding := renderer resourceCache rendererShaderSignature allocateMaterialState.
			binding
				writeState: material with: WDAGPUUnlitMaterialUniformBufferWriter;
				bindSampledTextureView: (self validTextureViewHandleFor: material colorTexture fallbackTextureWith: [renderer resourceCache whiteTexture2D]) inSlot: 1.
				
			activeSlabResource add: binding.
			binding
		]) bindingHandle;
		setVertexStage: (renderer resourceCache genericSurfaceMaterialVertexShaderWithLocationMask: locationMask) entryPoint: 'main';
		setFragmentStage: renderer resourceCache forwardUnlitFragmentShader entryPoint: 'main'.
	^ true
]

{ #category : #rendering }
WDAGPUSceneRendererActiveFrameRenderer >> finishExecution [
	commandQueue finishExecution.
	self freeActiveResources.
]

{ #category : #private }
WDAGPUSceneRendererActiveFrameRenderer >> freeActiveResources [
	activeSlabResource ifNotNil: [ 
		activeSlabResource do: [ :each | each free ].
		activeSlabResource := nil.
	].
	activeResources := nil.
	activeResourceDictionary := nil.
	self resetCurrentActiveState
]

{ #category : #rendering }
WDAGPUSceneRendererActiveFrameRenderer >> makeLightingStateForRenderingSceneState: renderingSceneState [
	^ WDLightingState new
		ambientLighting: renderingSceneState ambientLighting;
		lights: ((1 to: (renderingSceneState lights size min: 8)) collect: [:i |
			| light |
			light := renderingSceneState lights at: i.
			WDAGPUForwardLightState new
				positionOrDirection: Vector4 zeros;
				intensity: 0.0;
				spotDirection: Vector3 zeros;
				innerSpotCosCutoff: -1.0;
				outerSpotCosCutoff: -1.0;
				influenceRadius: 1.0;
				yourself.
		]) asArray;
		yourself
]

{ #category : #rendering }
WDAGPUSceneRendererActiveFrameRenderer >> recordAndFlushCommandsOn: aStateTracker queue: aCommandQueue with: aBlock [
	self beginRecordingCommandsOn: aStateTracker queue: aCommandQueue.
	[
		aBlock cull: self.
		stateTracker endRecordingAndFlushCommands
	] on: Error do: [ :e |
		self abortRecording.
		e pass
	]
]

{ #category : #rendering }
WDAGPUSceneRendererActiveFrameRenderer >> recordCommandsForRenderable: renderable [
	renderable emitRenderingCommandsWithRenderer: self
]

{ #category : #rendering }
WDAGPUSceneRendererActiveFrameRenderer >> recordCommandsForRenderingObject: renderingObject [
	self bindObjectState: renderingObject objectState.
	self recordCommandsForRenderable: renderingObject renderable
]

{ #category : #rendering }
WDAGPUSceneRendererActiveFrameRenderer >> recordRenderingCommandsFor: renderingSceneState intoFramebuffer: framebuffer [
	| framebufferHandle shaderSignature |
	framebufferHandle := self validFramebufferFor: framebuffer.
	shaderSignature := renderer resourceCache rendererShaderSignature.
	stateTracker
		beginRenderPass: renderer resourceCache viewportOutputRenderPass framebuffer: framebufferHandle bundle_content: 0;
		setViewport: 0 y: 0 w: framebuffer width h: framebuffer height;
		setScissor: 0 y: 0 w: framebuffer width h: framebuffer height;
		setShaderSignature: shaderSignature handle;
		useShaderResources: shaderSignature samplersBinding.

	self
		bindCameraState: (self convertedCameraState: renderingSceneState cameraState);
		bindLightingState: (self makeLightingStateForRenderingSceneState: renderingSceneState).
		
	renderingSceneState renderingObjects do: [ :each |
		self recordCommandsForRenderingObject: each
	].
	
		
	stateTracker endRenderPass
]

{ #category : #accessing }
WDAGPUSceneRendererActiveFrameRenderer >> renderer [

	^ renderer
]

{ #category : #accessing }
WDAGPUSceneRendererActiveFrameRenderer >> renderer: anObject [

	renderer := anObject
]

{ #category : #private }
WDAGPUSceneRendererActiveFrameRenderer >> resetCurrentActiveState [
	currentObjectVertexBinding := nil.
	currentObjectPrimitiveTopology := nil.
]

{ #category : #handles }
WDAGPUSceneRendererActiveFrameRenderer >> validBufferHandleForAccessor: aWDBinaryBufferAccessor [
	^ activeResourceDictionary at: aWDBinaryBufferAccessor ifAbsentPut: [
		| handle |
		handle := renderer resourceCache validBufferHandleForAccessor: aWDBinaryBufferAccessor.
		activeResources add: handle.
		handle
	]
]

{ #category : #handles }
WDAGPUSceneRendererActiveFrameRenderer >> validFramebufferFor: aWDFramebuffer [
	^ activeResourceDictionary at: aWDFramebuffer ifAbsentPut: [
		| handle |
		handle := renderer resourceCache validFramebufferFor: aWDFramebuffer.
		activeResources add: handle.
		handle
	]
]

{ #category : #'as yet unclassified' }
WDAGPUSceneRendererActiveFrameRenderer >> validTextureViewHandleFor: aWDTexture fallbackTextureWith: aBlock [
	aWDTexture ifNil: [ 
		^ aBlock value getOrCreateFullView
	].

	self halt
]

{ #category : #handles }
WDAGPUSceneRendererActiveFrameRenderer >> validVertexBindingFor: aWDVertexBufferBinding [
	^ activeResourceDictionary at: aWDVertexBufferBinding ifAbsentPut: [
		| handle |
		handle := renderer resourceCache validVertexBindingFor: aWDVertexBufferBinding.
		activeResources add: handle.
		handle
	]
]