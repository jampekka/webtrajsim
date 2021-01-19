{Scene} = require './scene.ls'
THREE = require 'three'
seqr = require './seqr.ls'
assets = require './assets.ls'
ui = require './ui.ls'
P = require 'bluebird'
{runScenario, newEnv} = require './scenarioRunner.ls'
{DirectionSound} = require './sounds.ls'
Co = P.coroutine
$ = require 'jquery'

runWithNewEnv = seqr.bind (scenario, ...args) ->*
	envP = newEnv!
	env = yield envP.get \env
	ret = yield scenario env, ...args
	envP.let \destroy
	yield envP
	return ret



exportScenario = (name, impl) ->
	scn = seqr.bind impl
	scn.scenarioName = name
	module.exports[name] = scn
	return scn

materialSign = (material) ->
	geo = new THREE.PlaneGeometry 1.0, 1.0
	new THREE.Mesh geo, material

targetMaterial = -> new THREE.ShaderMaterial do
		transparent: true
		uniforms:
			freq: value: 5.0
			radius: value: 1.0
			contrast: value: 1.0
		extensions: derivatives: true
		vertexShader: """
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
		\#define M_PI 3.1415926535897932384626433832795
		varying vec2 vUv;
		uniform float freq;
		uniform float radius;
		uniform float contrast;
		
		void main() {
			vec2 pos = (vUv - 0.5)*2.0;
			float r = length(pos);
			float or = length(vec2(pos.x, pos.y - 0.5));
			float value = cos(or*M_PI*10.5);
			value *= 0.5;
			value -= 0.5;
			value = (value + 1.0)/2.0;
			float aaf = 0.01;
			float edge = cos(r*M_PI*0.5)*step(r, 1.0);
			gl_FragColor = vec4(vec3(value), edge);
		}
		"""

crowdedC = (brightness=0.0) -> new THREE.ShaderMaterial do
		transparent: true
		uniforms:
			freq: value: 5.0
			radius: value: 1.0
			contrast: value: 1.0
			brightness: value: brightness
		extensions: derivatives: true
		vertexShader: """
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
		\#define M_PI 3.1415926535897932384626433832795
		varying vec2 vUv;
		uniform float freq;
		uniform float radius;
		uniform float contrast;
		uniform float brightness;

		// see: https://www.diva-portal.org/smash/get/diva2:618269/FULLTEXT02.pdf
		float aastep ( float distance ) {
			float threshold = 0.0;
			float afwidth = 0.7 * length ( vec2 ( dFdx ( distance ) , dFdy ( distance )) );
			return smoothstep ( threshold - afwidth , threshold + afwidth , distance );
		}

		float ring_sdf(float r_outer, float w, vec2 pos) {
			float r = length(pos);
			float r_inner = r_outer - w;
			float outer_d = r_outer - r;
			float inner_d = r_inner - r;
			return max(-outer_d, inner_d);
		}
		
		void main() {
			vec2 pos = (vUv - 0.5)*2.0;
			float r = length(pos);
			float r_ring = 1.0;
			float c = 1.0/5.0;
			float r_outer = r_ring/(1.0 + 4.0*c);
			float r_inner = r_outer*(1.0 - 2.0*c);
			float w = r_outer*2.0*c;

			//float aaf = fwidth(r);
			/*float outer = 1.0 - smoothstep(r_outer - aaf, r_outer, r);
			float inner = 1.0 - smoothstep(r_inner - aaf, r_inner, r);
			float value = 1.0 - inner;*/
			
			float outer_d = r_outer - r;
			float inner_d = r_inner - r;
			
			//float d = outer_d;
			//d = max(-d, inner_d);
			float d = ring_sdf(r_outer, w, pos);

			float box_d = abs(pos.x) - w/2.0;
			box_d = max(box_d, -pos.y);
			d = max(-box_d, d);
			
			d = min(d, ring_sdf(r_ring, w, pos));

			float alpha = 1.0 - aastep(d);
			//float value = cos(exp(d)*10.0); value = (value + 1.0)/2.0;

			//gl_FragColor = vec4(vec3(value), 1.0);
			gl_FragColor = vec4(vec3(brightness), alpha);
		}
		"""



cueMaterial = ->
	mat = new THREE.ShaderMaterial do
		transparent: true
		uniforms:
			opacity: value: 1.0

		extensions: derivatives: true
		vertexShader: """
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
		\#define M_PI 3.1415926535897932384626433832795
		varying vec2 vUv;
		uniform float opacity;

		
		void main() {
			float r = length((vUv - 0.5)*2.0);
			float value = cos(r*M_PI*4.5);
			value = (value + 1.0)/2.0;
			float aaf = 0.01;
			//float edge = 1.0 - smoothstep(1.0-aaf, 1.0, r);
			float edge = cos(r*M_PI*0.5)*step(r, 1.0);
			edge = mix(0.0, opacity, edge);
			gl_FragColor = vec4(vec3(value), edge);
		}
		"""
	Object.defineProperty mat, 'opacity',
		get: -> @uniforms.opacity.value
		set: (value) ->
			@uniforms.opacity.value = value
			console.log @uniforms
		configurable: true
		enumerable: true


export targetTest = (env) ->*
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
		bg = new THREE.Color()
		bg.setHSL(0.0, 0.0, 0.5)
		env.renderer.setClearColor bg, 1.0

	targetGeo = new THREE.PlaneGeometry 1.0, 1.0
	target = new THREE.Mesh targetGeo, targetMaterial()
	target.scale.set 0.3, 0.3, 0.3
	scene.visual.add target

	delay = (time, f) ->
		elapsed = 0.0
		scene.beforePhysics (dt) ->
			elapsed += dt
			return true if elapsed < time
			f()
			return false
	delayP = (time) -> new Promise (accept) -> delay time, accept

	@let \scene, scene
	scene.beforePhysics ->
		return
		target.material.uniforms.freq.value = (Math.sin(scene.time) + 1.0)/2.0*10.0 + 3.0;
	#while true
	#	c = Math.random() > 0.5
	#	target.material.uniforms.contrast.value = c
	#	yield delayP 1.0

	yield @get \done


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
	radius = 0.5
	roundsPerSecond = 0.3
	secondsPerRound = 1.0/roundsPerSecond

	scene.beforePhysics (dt) ->
		t = scene.time
		t = t*roundsPerSecond*Math.PI*2.0
		platform.position.x = (Math.sin t)*radius
		#platform.position.y = (Math.cos t)*radius

	delay = (time, f) ->
		elapsed = 0.0
		scene.beforePhysics (dt) ->
			elapsed += dt
			return true if elapsed < time
			f()
			return false
	delayFrames = (n) -> new P (accept) ->
		i = 0
		scene.beforePhysics (dt) !->
			i += 1
			if i >= n
				accept()
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

		target.signs.cue.material.opacity = 0.5
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

export baseScene = seqr.bind (env) ->*
	defaultParameters =
		speed: 1.3
		hideDuration: 0.3
		cueDuration: 1.0
		waitDuration: 1.0
		maskDuration: 0.3
		resultDuration: 2.0
		targetDuration: 0.05
		frequency: 5
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
		bg = new THREE.Color()
		bg.setHSL 0, 0, 0.5
		#bg.setHSL 0, 0, 0.0
		env.renderer.setClearColor bg

	platform = new THREE.Object3D()
	scene.visual.add platform

	#targetSign = materialSign targetMaterial()
	targetSign = materialSign crowdedC()
	targetSign.scale.set 0.5, 0.5, 0.5
	targetSign.scale.set 0.25, 0.25, 0.25
	target = yield assets.ArrowMarker()
	#target.setFrequency 20.0
	target.scale.set 0.3, 0.3, 0.3
	target.addSign 'target', targetSign

	cueSign = materialSign cueMaterial()
	cueSign.scale.set 0.5, 0.5, 0.5
	target.addSign 'cue', cueSign

	platform.add target

	scene.afterRender ->
		env.logger.write pdBase:
			time: scene.time
			platform: platform.matrix
			platformVisible: platform.visible
			targetVisible: target.visible
			targetSign: target.sign
			target: target.matrix
	assets.addMarkerScreen scene

	return scene: scene, platform: platform, target: target, parameters: parameters

Trialer = seqr.bind (env, defaultParams={}) ->*
	{scene, platform, target} = base = yield baseScene env
	keys = ['up', 'left', 'down', 'right']
	get_trial = seqr.bind (parameters={}) ->*
		parameters = Object.assign {}, base.parameters, defaultParams, parameters
		yield @get \run
		env.logger.write discriminationTrialStart: parameters
		target.setSign 'cue'
		yield scene.delay parameters.cueDuration
		target.setSign 'target'
		angle = Math.random()*Math.PI*2.0
		orientation = Math.floor(Math.random()*4)
		target.signs.target.rotation.z = orientation*Math.PI/2.0
		@let \target, keys[orientation]
		response = new P (accept) ->
			env.controls.change (key, isOn) !->
				return if not isOn
				return if key not in keys
				accept(key)
				return false
		yield scene.delay parameters.targetDuration
		@let \mask
		target.setSign 'mask'
		yield scene.delay parameters.maskDuration
		@let \query
		target.setSign 'query'
		response = yield response
		targetKey = keys[orientation]
		correct = targetKey == response
		env.logger.write discriminationTrialResponse:
			targetKey: targetKey
			responseKey: response
			wasCorrect: correct
		@let \response, correct
		if correct
			target.setSign 'success'
		else
			target.setSign 'failure'
		yield scene.delay parameters.waitDuration
		target.setSign 'cue'
		return correct


	get_trial.scene = scene
	get_trial.platform = platform
	get_trial.target = target
	get_trial.parameters = base.parameters

	return get_trial


class Staircase
	({@value, @stepUp, @target_p=0.7, @min, @max}) ->
		@stepDown = @stepUp*((1 - @target_p)/@target_p)
		@values = []
		@results = []
		@reversals = []

	measurement: (r) ->
		@values.push @value
		if @results.length and @results[*-1] != r
			@reversals.push @results.length
		@results.push r
		if not r
			@value += @stepUp
		else
			@value -= @stepDown

		if @min? and @value < @min
			@value = @min
		if @max? and @value > @max
			@value = @max

	estimate: ->
		if @reversals.length == 0
			return @value
		total = [@values[i] for i in @reversals].reduce((+))
		return total/@reversals.length

exportScenario \visionTestPractice, (env, params={}) ->*
	defaultTestParams =
		targetScale: 0.5
		practiceTargetDuration: 1.0
		jitterRadius: 0.05
		correctNeeded: 4

	L = env.L
	@let \intro,
		title: L "Vision test"
		subtitle: L "Practice"
		content: L "VISION_TEST_PRACTICE"

	{platform, scene, target} = trialer = yield Trialer env

	parameters = Object.assign {}, trialer.parameters, defaultTestParams, params
	s = parameters.targetScale
	target.signs.target.scale.set s, s, s

	untilPassed = seqr.bind (duration, jitter=0) ->*
		corrects = 0
		while corrects < parameters.correctNeeded
			trial = trialer(parameters with targetDuration: duration)
			trial.let \run
			angle = Math.random()*Math.PI*2.0
			yield trial.get \target
			platform.position.x = Math.sin(angle)*jitter
			platform.position.y = Math.cos(angle)*jitter
			yield trial.get \query
			platform.position.x = 0
			platform.position.y = 0
			correct = yield trial
			if correct
				corrects += 1
			else
				corrects = 0

	@let \scene, scene
	yield @get \run
	yield untilPassed parameters.practiceTargetDuration

	yield ui.instructionScreen env, ->
		@ \title .text L "Vision test"
		@ \subtitle .text L "Flash practice"
		@ \content .text L "VISION_TEST_PRACTICE_FLASH"
	yield untilPassed parameters.targetDuration

	yield ui.instructionScreen env, ->
		@ \title .text L "Vision test"
		@ \subtitle .text L "Peripheral flash practice"
		@ \content .text L "VISION_TEST_PRACTICE_JITTER"
	yield untilPassed parameters.targetDuration, defaultTestParams.jitterRadius
	
	@let \done
	return
		passed: true


exportScenario \visionTest, (env, params={}) ->*
	defaultTestParams =
		initialValue: 0.3
		minValue: 0.05
		maxValue: 0.7
		nReversals: 20
		maxTrials: 100
		stepUp: 0.05
		jitterRadius: 0.0
	parameters = Object.assign {}, defaultTestParams, params
	stairs = new Staircase do
		value: parameters.initialValue
		stepUp: parameters.stepUp
		min: parameters.minValue
		max: parameters.maxValue

	L = env.L
	@let \intro,
		title: L "Vision test"
		content: L "VISION_TEST"

	{platform} = trialer = yield Trialer env
	@let \scene trialer.scene
	yield @get \run
	while stairs.reversals.length < parameters.nReversals and stairs.results.length < parameters.maxTrials
		s = stairs.value
		trialer.target.signs.target.scale.set s, s, s
		trial = trialer()
		trial.let \run
		yield trial.get \target
		angle = Math.random()*Math.PI*2.0
		platform.position.x = Math.sin(angle)*parameters.jitterRadius
		platform.position.y = Math.cos(angle)*parameters.jitterRadius
		yield trial.get \query
		platform.position.x = 0
		platform.position.y = 0
		correct = yield trial
		stairs.measurement correct


	@let \done,
		passed: true
		result:
			stairs: stairs

	return yield @get \done

{knuthShuffle: shuffleArray} = require 'knuth-shuffle'
exportScenario \peripheralVisionTest, (env, params={}) ->*
	L = env.L

	@let \intro,
		title: L "Peripheral vision test"
		content: L "PERIPHERAL_VISION_TEST"


	{platform, target} = trialer = yield Trialer env

	if params.targetSize?
		scale = params.targetSize
		target.signs.target.scale.set scale, scale, scale


	radii = [].concat [0.05]*10, [0.1]*10, [0.2]*10, [0.3]*10, [0.4]*10
	radii = shuffleArray radii

	@let \scene trialer.scene
	yield @get \run
	for radius in radii
		trial = trialer()
		trial.let \run
		yield trial.get \target
		angle = Math.random()*Math.PI*2.0
		platform.position.x = Math.sin(angle)*radius
		platform.position.y = Math.cos(angle)*radius
		yield trial.get \query
		platform.position.x = 0
		platform.position.y = 0
		correct = yield trial

	@let \done
	return passed: true

uniform = (min, max) -> Math.random()*(max - min) + min

exportScenario \fall, (env, params={}) ->*
	params.nTrials ?= 30
	params.maxBlindDur ?= Infinity
	params.maxHintDur ?= 1.0
	params.minHintDur ?= 0.1
	bounce_k = -0.5

	L = env.L
	@let \intro,
		title: L "Falling motion"
		content: L if params.maxBlindDur > 0 then "FALLING_MOTION_BLIND" else "FALLING_MOTION"


	s = 0.9

	aspect = screen.width/screen.height

	ys = 1.0 - 0.1
	xs = aspect - 0.3

	start_pos = x: 0.0, y: ys
	gravity = x: 0.0, y: -0.5

	trialer = {platform, target, scene} = yield Trialer(env, params)
	if params.targetSize?
		scale = params.targetSize
		target.signs.target.scale.set scale, scale, scale

	reset_position = seqr.bind ->*
		vel =
			x: (start_pos.x - platform.position.x)*1.0
			y: (start_pos.y - platform.position.y)*1.0
		speed = Math.sqrt vel.x**2 + vel.y**2
		vel.x /= speed
		vel.y /= speed
		vel.x *= 2.0
		vel.y *= 2.0
		x_direction = Math.sign vel.x
		scene.beforePhysics (dt) !~>
			platform.position.x += vel.x*dt
			platform.position.y += vel.y*dt
			if Math.sign(platform.position.x - start_pos.x) == x_direction
				platform.position.x = start_pos.x
				platform.position.y = start_pos.y
				@let \quit
				return false
		yield @get \quit


	go_ballistic = seqr.bind (launch_speed) ->*
		vel = launch_speed
		cb = scene.beforePhysics (dt) !->
			platform.position.x += vel.x*dt
			platform.position.y += vel.y*dt
			vel.y += gravity.y*dt
			vel.x += gravity.x*dt
			if platform.position.y > ys
				platform.position.y = ys
				vel.y *= bounce_k
				vel.x *= -bounce_k
			if platform.position.y < -ys
				platform.position.y = -ys
				vel.y *= bounce_k
				vel.x *= -bounce_k
			if platform.position.x > xs
				platform.position.x = xs
				vel.x *= bounce_k
				vel.y *= -bounce_k
			if platform.position.x < -xs
				platform.position.x = -xs
				vel.x *= bounce_k
				vel.y *= -bounce_k

		yield @get \quit
		scene.beforePhysics.remove(cb)

	fall_duration = Math.sqrt(2*(-s - start_pos.y)/gravity.y)
	console.log (start_pos.y - -ys)
	width = Math.abs xs - start_pos.x
	max_speed = width/fall_duration


	target.setSign 'cue'
	@let \scene, scene
	yield @get \run
	yield reset_position()
	console.log params
	for i from 0 til params.nTrials
		launch_speed =
			y: 0, x: uniform(-max_speed, max_speed)

		end_at = fall_duration*0.9
		hint_dur = uniform (params.minHintDur), end_at*(params.maxHintDur)
		blind_dur = end_at - hint_dur
		blind_dur = uniform 0.0, Math.min(blind_dur, params.maxBlindDur)
		trial = trialer cueDuration: hint_dur + blind_dur

		yield scene.delay 1.0
		trial.let \run
		traj = go_ballistic launch_speed

		yield scene.delay hint_dur
		target.visible = false

		yield trial.get \target
		target.visible = true

		yield trial
		traj.let \quit ; yield traj
		yield reset_position()
		#trial = trialer()
		#trial \let @run

	@let \done
	return passed: true

exportScenario \linear, (env, params={}) ->*
	params.nTrials ?= 30
	params.maxBlindDur ?= Infinity
	params.maxHintDur ?= 0.5
	params.minHintDur ?= 0.1
	params.minSpeed ?= 1.0
	params.maxSpeed ?= 2.0
	L = env.L
	@let \intro,
		title: L "Constant speed"
		content: L if params.maxBlindDur > 0 then "CONSTANT_SPEED_BLIND" else "CONSTANT_SPEED"

	aspect = screen.width/screen.height

	#ys = 1.0 - 0.1
	xs = (aspect - 0.3) - 0.3

	trialer = {platform, target, scene} = yield Trialer(env, params)
	if params.targetSize?
		scale = params.targetSize
		target.signs.target.scale.set scale, scale, scale

	go_linear = seqr.bind (launch_speed) ~>*
		direction = -Math.sign platform.position.x
		vel = direction*launch_speed
		cb = scene.beforePhysics (dt) !~>
			platform.position.x += vel*dt
			if direction < 0 and platform.position.x < -xs
				platform.position.x = -xs
				@let \quit
				return false
			if direction > 0 and platform.position.x > xs
				platform.position.x = xs
				@let \quit
				return false
		yield @get \quit

	target.setSign 'cue'
	platform.position.x = -xs
	@let \scene, scene
	yield @get \run
	for i from 0 til params.nTrials
		launch_speed = uniform params.minSpeed, params.maxSpeed
		traj_dur = 2*xs/launch_speed
		end_at = traj_dur*0.9
		hint_dur = uniform (params.minHintDur), end_at*(params.maxHintDur)
		blind_dur = end_at - hint_dur
		blind_dur = uniform 0.0, Math.min(blind_dur, params.maxBlindDur)
		trial = trialer cueDuration: hint_dur + blind_dur

		yield scene.delay 1.0
		trial.let \run
		traj = go_linear launch_speed

		yield scene.delay hint_dur
		target.visible = false

		yield trial.get \target
		target.visible = true

		yield trial
		yield traj

	@let \done
	return passed: true


exportScenario \swing, (env, params={}) ->*
	params.nTrials ?= 30
	params.maxBlindDur ?= 3.0
	params.maxHintDur ?= 2.0
	params.minHintDur ?= 1.0
	params.doBlind ?= true
	params.x_amp ?= 0.6
	params.y_amp ?= 0.0
	
	sound = yield DirectionSound(env)

	L = env.L
	@let \intro,
		title: L "Circular motion"
		content: L if params.doBlind then "CIRCULAR_MOTION_BLIND" else "CIRCULAR_MOTION"


	trialer = {platform, target, scene} = yield Trialer(env, params)

	if params.targetSize?
		scale = params.targetSize
		target.signs.target.scale.set scale, scale, scale

	scene.beforePhysics ->
		t = scene.time*(Math.PI*2.0)/4.0
		platform.position.x = params.x_amp*Math.sin t
		platform.position.y = params.y_amp*Math.cos t
		sound.setPosition platform.position.x, platform.position.y

	@let \scene scene
	yield @get \run
	sound.start()
	for i from 0 til params.nTrials
		hint_dur = uniform params.minHintDur, params.maxHintDur
		blind_dur = uniform 0.0, params.maxBlindDur
		trial = trialer cueDuration: hint_dur + blind_dur
		trial.let \run
		yield scene.delay hint_dur
		if params.doBlind
			target.visible = false
			yield trial.get \target
			target.visible = true
		yield trial

	sound.stop()
	@let \done
	return passed: true

export stimtest = (env) ->*
	console.log "Here"
	{scene, platform, target, parameters} = base = yield baseScene env

	target.scale.set 3.0, 3.0, 3.0
	target.setSign 'target'
	@let \scene scene

	yield @get \done


export calib_dialog = seqr.bind (env, params={}) ->*
	nocontrol = env with controls: change: ->
	L = env.L

	task = ui.instructionScreen nocontrol, ->
		@ \title .append L "Eye-tracker calibration"
		if params.isFull
			@ \title .append "*"
		@ \content .append L "EYE_TRACKER_CALIBRATION"
		@ \accept-button .hide()
		$("body").keyup (e) ->
			if e.which == 89
				task.let \accept
	yield task
	return

