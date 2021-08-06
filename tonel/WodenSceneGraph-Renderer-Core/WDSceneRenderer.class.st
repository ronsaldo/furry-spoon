"
I am the interface for a scene renderer.
"
Class {
	#name : #WDSceneRenderer,
	#superclass : #Object,
	#classVars : [
		'Current',
		'CurrentSession'
	],
	#category : #'WodenSceneGraph-Renderer-Core-WodenSceneGraph-Renderer-Core'
}

{ #category : #accessing }
WDSceneRenderer class >> current [
	(Current isNil or: [CurrentSession ~~ Smalltalk session]) ifTrue: [ 
		Current := self pick new.
		CurrentSession := Smalltalk session
	].
	^ Current
]

{ #category : #testing }
WDSceneRenderer class >> isAbstract [
	^ self == WDSceneRenderer
]

{ #category : #testing }
WDSceneRenderer class >> isAvailable [
	^ false
]

{ #category : #private }
WDSceneRenderer class >> pick [
	self allSubclassesDo: [ :each |
		each isAvailable ifTrue: [ ^ each ]
	].
	^ WDNullSceneRenderer
]

{ #category : #initialization }
WDSceneRenderer class >> reset [
	<script>
	Current := nil
]

{ #category : #rendering }
WDSceneRenderer >> renderSceneState: renderingSceneState intoFramebuffer: framebuffer [
	self subclassResponsibility
]