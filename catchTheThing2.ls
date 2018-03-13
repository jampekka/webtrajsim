{Scene} = require './scene.ls'

assets = require './assets.ls'
P = require 'bluebird'
Co = P.coroutine

gratingMaterial = -> new THREE.ShaderMaterial do
		uniforms:
			freq: value: 10.0
		extensions: derivatives: true
		vertexShader: """
		uniform float freq;
		varying vec2 vUv;
		varying vec4 mvPosition;
		void main()
		{
			vUv = uv;
			mvPosition = modelViewMatrix * vec4( position, 1.0 );
			vec4 wPosition = modelMatrix * vec4(position, 1.0);
			gl_Position = projectionMatrix * mvPosition;
		}
		"""

		fragmentShader: """
		\#extension GL_OES_standard_derivatives : enable
		\#define M_PI 3.1415926535897932384626433832795
		varying vec2 vUv;
		
		float gradInt(float t) {
			return 0.5*(t - cos(t));
		}

		void main() {
			float t = vUv.x*freq*M_PI*2.0;
			float dt = fwidth(t);
			float t0 = t - dt/2.0;
			float t1 = t + dt/2.0;
			float value = (gradInt(t1) - gradInt(t0))/dt; //(sin(t) + 1.0)/2.0;
			float radius = length((vUv - 0.5)*2.0);
			value *= 1.0 - smoothstep(0.5, 1.0, radius);
			float contrast = 1.0;
			float min = 0.5*(1.0 - contrast);
			//value = mix(min, 1.0 - min, value);
			gl_FragColor = vec4(vec3(value), 1.0);
		}
		"""


export catchTheThing = (env) ->*
	defaultParameters =
		speed: 1.3
		hideDuration: 0.3
		cueDuration: 2.0
		waitDuration: 2.0
		maskDuration: 0.3
		resultDuration: 2.0
		targetDuration: 0.05
		frequency: 10
		manipulation: 0
	parameters = defaultParameters
	
	camera = new THREE.OrthographicCamera -1, 1, -1, 1, 0.1, 10
			..position.z = 5
	env.onSize (w, h) ->
		w = w/h
		h = 1
		camera.left = -w
		camera.right = w
		camera.bottom = -h
		camera.top = h
		camera.updateProjectionMatrix!
	scene = new Scene camera: camera
	scene.visual.add new THREE.AmbientLight 0xffffff
	scene.preroll = ->

	platform = new THREE.Object3D()
	scene.visual.add platform

	target = yield assets.ArrowMarker()
	target.setFrequency 8.0
	target.scale.set 0.3, 0.3, 0.3
	target.signs.target.scale.set 0.3, 0.3, 0.3
	platform.add target

	zoomtime = 0.0
	radius = 0.3
	roundsPerSecond = 0.2
	secondsPerRound = 1.0/roundsPerSecond

	scene.beforePhysics (dt) ->
		t = scene.time
		t = t*roundsPerSecond*Math.PI*2.0
		platform.position.x = (Math.sin t)*radius
		platform.position.y = (Math.cos t)*radius

	delay = (time, f) ->
		elapsed = 0.0
		scene.beforePhysics (dt) ->
			elapsed += dt
			return true if elapsed < time
			f()
			return false

	delayP = (time) -> new Promise (accept) -> delay time, accept
	waitFor = (f) -> new P (accept) -> f (accept)

	@let \scene, scene

	uniform = (min, max) -> Math.random()*(max - min) + min

	target.setSign 'cue'
	blindAlpha = 0.5
	minBlindAlpha = 0.01
	runTrial = Co ->*
		target.signs.target.rotation.z = Math.sign(Math.random() - 0.5)*Math.PI/4.0
		target.setSign 'cue'
		target.signs.cue.material.opacity = 0.5
		yield delayP uniform 1.0, 4.0
		target.signs.cue.material.opacity = 1.0
		yield delayP 1.0

		target.visible = false
		target.setSign 'target'
		yield delayP uniform 0.0, secondsPerRound

		target.visible = true
		yield delayP parameters.targetDuration
		target.setSign 'mask'

		yield delayP parameters.maskDuration

		target.setSign 'query'

		keys = ['left', 'right']
		response = yield new P (accept) ->
			env.controls.change (key, isOn) !->
				return if not isOn
				return if key not in keys
				accept(key)
				return false
		targetKey = keys[(target.signs.target.rotation.z < 0)*1]
		if targetKey == response
			target.setSign 'success'
		else
			target.setSign 'failure'

		yield delayP 2.0


	while true
		yield runTrial()


	return yield @get \done
