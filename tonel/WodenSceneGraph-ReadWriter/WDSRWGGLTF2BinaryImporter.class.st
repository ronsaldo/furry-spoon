Class {
	#name : #WDSRWGGLTF2BinaryImporter,
	#superclass : #WDSRWGGLTF2Importer,
	#instVars : [
		'chunks'
	],
	#category : #'WodenSceneGraph-ReadWriter-GLTF2'
}

{ #category : #documentation }
WDSRWGGLTF2BinaryImporter class >> readFromFileReference: aFileReference [
	^ self new readFromFileReference: aFileReference
]

{ #category : #loading }
WDSRWGGLTF2BinaryImporter >> getBinaryDataChunkWithIndex: binaryChunkIndex [
	| chunk |
	chunk := (chunks at: binaryChunkIndex + 1).
	chunk isBinary ifFalse: [ 
		self error: 'Expected a binary chunk.'
	].

	^ chunk content
]

{ #category : #loading }
WDSRWGGLTF2BinaryImporter >> readFromFileReference: fileReference [
	| version length gltfJson |
	chunks := OrderedCollection new.
	
	fileReference binaryReadStreamDo: [ :in |
		(in next: 4) = 'glTF' asByteArray ifFalse: [ 
			self error: 'glTF binary with invalid magic number.'.
		].
		version := in nextLittleEndianNumber: 4.
		length := in nextLittleEndianNumber: 4.
		version = 2 ifFalse: [ 
			self error: 'Unsupported glTF version ', version asString , '.'
		].
	
		self readGLTFChunksFrom: in until: in position + length - 12
	].

	chunks first isJSON ifFalse: [ 
		self error: 'The first chunk of a GLTF 2 binary file is expected to be a JSON.'
	].

	gltfJson := (NeoJSONReader on: chunks first utf8ReadStream) next.
	^ self
		loadingDirectory: fileReference asAbsolute parent;
		processGLTFJson: gltfJson
]

{ #category : #loading }
WDSRWGGLTF2BinaryImporter >> readGLTFChunkFrom: in [
	| chunkLength chunkType chunkPayload |
	chunkLength := in nextLittleEndianNumber: 4.
	chunkType := in next: 4.
	chunkPayload := in next: chunkLength.
	chunks add: (WDSRWGGLTF2BinaryChunk new
		type: chunkType;
		content: chunkPayload;
		yourself
	)
]

{ #category : #loading }
WDSRWGGLTF2BinaryImporter >> readGLTFChunksFrom: in until: targetPosition [
	[in position < targetPosition] whileTrue: [ 
		self readGLTFChunkFrom: in
	]
]