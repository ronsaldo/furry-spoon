"
I am a scene renderer that does nothing.
"
Class {
	#name : #WDNullSceneRenderer,
	#superclass : #WDSceneRenderer,
	#category : #'WodenSceneGraph-Renderer-Core-WodenSceneGraph-Renderer-Core'
}

{ #category : #rendering }
WDNullSceneRenderer >> renderSceneState: renderingSceneState intoFramebuffer: framebuffer [
	"Nothing is required here."
]