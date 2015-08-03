P = require 'bluebird'
Co = P.coroutine
$ = require 'jquery'
seqr = require './seqr.ls'

{addGround, Scene} = require './scene.ls'
{addVehicle} = require './vehicle.ls'
{NonSteeringControl} = require './controls.ls'
{DefaultEngineSound} = require './sounds.ls'
assets = require './assets.ls'

# Just a placeholder for localization
L = (s) -> s

ui = require './ui.ls'

DummyScene = ->
	beforePhysics: Signal!
	afterPhysics: Signal!
	beforeRender: Signal!
	onRender: Signal!
	onStart: Signal!
	onExit: Signal!
	onTickHandled: Signal!
	#camera: new THREE.PerspectiveCamera!
	camera:
		updateProjectionMatrix: ->
		add: ->
	#visual: new THREE.Scene!
	visual:
		add: ->
		traverse: ->
		addEventListener: ->
	physics:
		add: ->
		addEventListener: ->
		removeBody: ->
	preroll: ->
	tick: ->
	bindPhys: ->
#Scene = DummyScene

export baseScene = seqr.bind (env) ->*
	{controls, audioContext} = env
	scene = new Scene
	yield P.resolve addGround scene
	sky = yield P.resolve assets.addSky scene

	scene.playerControls = controls

	player = yield addVehicle scene, controls
	player.eye.add scene.camera
	player.physical.position.x = -1.75
	scene.player = player

	scene.player.speedometer = ui.gauge env,
		name: L "Speed"
		unit: L "km/h"
		value: ->
			speed = scene.player.getSpeed()*3.6
			Math.round speed

	engineSounds = yield DefaultEngineSound audioContext
	gainNode = audioContext.createGain()
	gainNode.connect audioContext.destination
	engineSounds.connect gainNode
	scene.afterPhysics.add ->
		rev = Math.abs(player.getSpeed())/(200/3.6)
		rev = Math.max 0.1, rev
		rev = (rev + 0.1)/1.1
		gain = scene.playerControls.throttle
		gain = (gain + 0.5)/1.5
		gainNode.gain.value = gain
		engineSounds.setPitch rev*2000
	scene.onStart.add engineSounds.start
	scene.onExit.add engineSounds.stop

	scene.preroll = ->
		# Tick a couple of frames for the physics to settle
		scene.tick 1/60
		n = 100
		t = Date.now()
		for [0 to n]
			scene.tick 1/60
		console.log "Prewarming FPS", (n/(Date.now() - t)*1000)
	return scene

export minimalScenario = seqr.bind (env) ->*
	scene = new Scene
	addGround scene
	scene.preroll = ->
	@let \scene, scene
	yield @get \done

export freeDriving = seqr.bind (env) ->*
	# Load the base scene
	scene = yield baseScene env

	# The scene would be customized here

	# "Return" the scene to the caller, so they know
	# we are ready
	@let \scene, scene

	# Run until somebody says "done".
	yield @get \done

export basePedalScene = (env) ->
	env = env with
		controls: NonSteeringControl env.controls
	return baseScene env

catchthething = require './catchthething.ls'
addReactionTest = seqr.bind (scene, env) ->*
	react = yield catchthething.React()
	screen = yield assets.SceneDisplay()

	screen.object.position.z = -0.3
	screen.object.scale.set 0.12, 0.12, 0.12
	screen.object.visible = false
	#screen.object.position.y = 2
	#screen.object.rotation.y = Math.PI
	scene.camera.add screen.object

	env.controls.change (btn, isOn) !->
		if btn == "catch" and isOn and screen.object.visible
			react.catch()
		else if btn == "blinder"
			screen.object.visible = isOn

	react.event (type) ->
		env.logger.write reactionGameEvent: type

	scene.onRender.add (dt) ->
		react.tick dt
		env.renderer.render react.scene, react.camera, screen.renderTarget, true
		#env.renderer.render react.scene, react.camera

	return react


addBlinderTask = (scene, env) ->
	mask = new THREE.Mesh do
		new THREE.PlaneGeometry 0.14*16/9, 0.14
		new THREE.MeshBasicMaterial color: 0x000000
	mask.position.z = -0.3
	scene.camera.add mask

	self =
		change: Signal!
		glances: 0

	showMask = ->
		mask.visible = true
		self.change.dispatch true
		env.logger.write blinder: true
	showMask()

	ui.gauge env,
		name: L "Glances"
		unit: ""
		value: ->
			self.glances


	env.controls.change (btn, isOn) ->
		return if btn != 'blinder'
		return if isOn != true
		return if not mask.visible
		mask.visible = false
		self.glances += 1
		self.change.dispatch false
		env.logger.write blinder: false
		setTimeout showMask, 300

	return self


export runTheLight = seqr.bind (env) ->*
	@let \intro,
		title: L "Run the light"
		subtitle: L "(Just this once)"
		content: $ L """
			<p>From here on you must honor the traffic light.
			But go ahead and run it once so you know what happens.</p>

			<p>Press enter or click the button below to continue.</p>
			"""

	scene = yield basePedalScene env
	startLight = yield assets.TrafficLight()
	startLight.position.x = -4
	startLight.position.z = 6
	startLight.addTo scene

	@let \scene, scene
	yield @get \run

	scene.player.onCollision (e) ~>
		@let \done, passed: true, outro:
			title: L "Passed"
			content: L """
				From here on, the trial will be disqualified if you
				run any red lights.
				"""

	return yield @get \done

export throttleAndBrake = seqr.bind (env) ->*
	@let \intro,
		title: L "Throttle and brake"
		content: L """
			Let's get familiar with the car. Get across the finish line
			as soon as possible, but without running any red lights.
			"""

	scene = yield basePedalScene env

	goalDistance = 200
	startLight = yield assets.TrafficLight()
	startLight.position.x = -4
	startLight.position.z = 6
	startLight.addTo scene

	endLight = yield assets.TrafficLight()
	endLight.position.x = -4
	endLight.position.z = goalDistance + 10
	endLight.addTo scene

	scene.player.onCollision (e) ~>
		@let \done, passed: false, outro:
			title: L "Oops!"
			content: L "You ran the red light!"
		return false

	finishSign = yield assets.FinishSign!
	finishSign.position.z = goalDistance
	scene.visual.add finishSign
	ui.gauge env,
		name: L "Time"
		unit: "s"
		value: ->
			if not startTime?
				return 0.toFixed 2
			(scene.time - startTime).toFixed 2


	@let \scene, scene
	yield @get \run

	yield P.delay 1000
	yield startLight.switchToGreen()
	startTime = scene.time

	scene.onTickHandled ~>
		return if Math.abs(scene.player.getSpeed()) > 0.1
		return if scene.player.physical.position.z < goalDistance

		time = scene.time - startTime
		@let \done, passed: true, outro:
			title: L "Passed!"
			content: L "Your time was <strong>#{time.toFixed 2}</strong> seconds."
		return false

	return yield @get \done

export speedControl = seqr.bind (env) ->*
	@let \intro,
		title: L "Speed control"
		content: L """
			<p>Drive as fast as possible, yet honoring the speed limits,
			and of course the red lights. More you drive over the speed limit,
			the more penalty time you get.
			"""

	scene = yield basePedalScene env
	limits = [
		[-Infinity, 50]
		[20, 50]
		[200, 30]
		[250, 80]
		[500, 60]
	]
	goalDistance = 700

	for [dist, limit] in limits
		sign = yield assets.SpeedSign limit
		sign.position.z = dist
		sign.position.x = -4
		scene.visual.add sign
	limits.reverse()
	currentLimit = ->
		mypos = scene.player.physical.position.z
		for [distance, limit] in limits
			break if distance < mypos

		return limit

	limitSign = ui.gauge env,
		name: L "Speed limit"
		unit: L "km/h"
		value: currentLimit

	illGainsMultiplier = 10
	illGains = 0
	timePenalty = 0
	scene.afterPhysics (dt) ->
		return if not startTime?
		limit = currentLimit!
		speed = Math.abs scene.player.getSpeed()*3.6
		if speed <= limit
			limitSign.normal()
			return

		limitSign.warning()
		traveled = (speed/3.6)*dt
		legalMinTime = traveled/(limit/3.6)
		timeGained = legalMinTime - dt

		illGains += timeGained
		timePenalty := illGains*illGainsMultiplier

	ui.gauge env,
		name: "Penalty"
		unit: "s"
		value: ->
			timePenalty.toFixed 2

	startLight = yield assets.TrafficLight()
	startLight.position.x = -4
	startLight.position.z = 6
	startLight.addTo scene

	endLight = yield assets.TrafficLight()
	endLight.position.x = -4
	endLight.position.z = goalDistance + 10
	endLight.addTo scene

	scene.player.onCollision (e) ~>
		@let \done, passed: false, outro:
			title: L "Oops!"
			content: L "You ran the red light!"
		return false

	finishSign = yield assets.FinishSign!
	finishSign.position.z = goalDistance
	scene.visual.add finishSign

	@let \scene, scene
	yield @get \run

	yield P.delay 1000
	yield startLight.switchToGreen()
	startTime = scene.time

	scene.onTickHandled ~>
		return if Math.abs(scene.player.getSpeed()) > 0.1
		return if scene.player.physical.position.z < goalDistance

		time = scene.time - startTime
		@let \done, passed: true, outro:
			title: L "Passed!"
			content: L """
				You ran the course in #{time.toFixed 2} seconds, but got
				#{timePenalty.toFixed 2} seconds penalty from breaking the
				limit. The final score is #{(timePenalty + time).toFixed 2} seconds.
				"""
		return false

	return yield @get \done

export blindSpeedControl = seqr.bind (env) ->*
	base = speedControl env

	intro = yield base.get \intro
	@let \intro,
		title: L "Anticipatory speed control"
		content: L """
			<p>Drive as fast as possible, yet honoring the speed limits,
			and of course the red lights.

			<p>In this task also your level of anticipation is measured by
			the number of glances you have to take. To briefly see the road,
			press the left lever. Try to accomplish the task as well as you can,
			while taking as few glances as you can.
			"""

	scene = yield base.get \scene

	addBlinderTask scene, env
	@let \scene, scene

	yield @get \run
	base.let \run

	result = yield base.get \done

	@let \done, result

	return result


{IdmVehicle, LoopMicrosim} = require './microsim.ls'

class MicrosimWrapper
	(@phys) ->
	position:~->
		@phys.position.z
	velocity:~->
		@phys.velocity.z

	acceleration:~-> null

	step: ->


export followInTraffic = seqr.bind (env) ->*
	@let \intro,
		title: L "Supermiler"
		content: $ L """
			<p>Drive in the traffic trying to get as much mileage as you
			can.
			
			<p>Note that closer you drive to vehicle before you, the less fuel
			you consume due to the lesser air resistance. But you waste good momentum
			by braking, so try to find a balance where you can keep a short
			headway without having to brake too much.

			<p>There are no speed limits in this task.
			"""

	scene = yield basePedalScene env
	#addReactionTest scene, env
	#addBlinderTask scene, env

	startLight = yield assets.TrafficLight()
	startLight.position.x = -4
	startLight.position.z = 6
	startLight.addTo scene

	goalDistance = 2000
	finishSign = yield assets.FinishSign!
	finishSign.position.z = goalDistance
	scene.visual.add finishSign

	scene.player.onCollision (e) ~>
		reason = L "You crashed!"
		if e.body.objectClass == "traffic-light"
			reason = L "You ran the red light!"
		@let \done, passed: false, outro:
			title: L "Oops!"
			content: reason
		return false

	maximumFuelFlow = 200/60/1000
	constantConsumption = maximumFuelFlow*0.1
	draftingCoeff = (d) ->
		# Estimated from Mythbusters!
		Math.exp(0) - Math.exp(-(d + 5.6)*0.1)

	consumption =
		time: 0
		distance: 0
		instant: 0
		total: 0
		noDraftTotal: 0
		avgLitersPer100km: (consumption=@total) ->
			metersPerLiter = @distance/consumption
			1.0/metersPerLiter*1000*100
		instLitersPer100km: ->
			metersPerLiter = Math.abs(scene.player.getSpeed())/@instant
			1.0/metersPerLiter*1000*100

	scene.afterPhysics.add (dt) !->
		return if not startTime?
		consumption.time += dt
		consumption.distance += dt*Math.abs(scene.player.getSpeed())
		instant = env.controls.throttle*maximumFuelFlow + constantConsumption
		consumption.instant = instant * draftingCoeff(distanceToLeader!)
		consumption.total += consumption.instant*dt
		consumption.noDraftTotal += instant*dt

	ui.gauge env,
		name: L "Current consumption"
		unit: "l/100km"
		range: [0, 30]
		format: (v) ->
			if Math.abs(scene.player.getSpeed()) < 1.0
				return null
			return v.toFixed 2
		value: ->
			c = consumption.instLitersPer100km!
			return c

	ui.gauge env,
		name: L "Average consumption"
		unit: "l/100km"
		range: [0, 30]
		format: (v) ->
			return null if consumption.distance < 1
			return v.toFixed 2
		value: ->
			return consumption.avgLitersPer100km!

	nVehicles = 20
	spacePerVehicle = 20
	traffic = new LoopMicrosim nVehicles*spacePerVehicle
	for i in [1 til nVehicles]
		v = new IdmVehicle do
			a: 4.0
			b: 10.0
			timeHeadway: 1.0
		v.position = i*spacePerVehicle
		traffic.addVehicle v
	scene.beforePhysics.add traffic~step
	scene.traffic = traffic

	playerSim = new MicrosimWrapper scene.player.physical
	traffic.addVehicle playerSim

	leader = yield addVehicle scene
	leader.physical.position.z = playerSim.leader.position
	leader.physical.position.x = -1.75
	scene.beforeRender.add (dt) ->
		leader.forceModelSync()
		leader.physical.position.z = playerSim.leader.position
		leader.forceModelSync()

	headway =
		cumulative: 0
		time: 0
		average: ->
			@cumulative/@time
	cumHeadway = 0
	averageHeadway = 0
	scene.afterPhysics (dt) ->
		return if not startTime?
		headway.cumulative += dt*distanceToLeader!
		headway.time += dt


	distanceToLeader = ->
		rawDist = scene.player.physical.position.distanceTo leader.physical.position
		return rawDist - scene.player.physical.boundingRadius - leader.physical.boundingRadius

	scene.draftIndicator = ui.gauge env,
		name: L "Draft saving"
		unit: "%"
		#range: [0, 30]
		#format: (v) ->
		#	return null if consumption.distance < 1
		#	return v.toFixed 2
		value: ->
			c = draftingCoeff distanceToLeader!
			((1 - c)*100).toFixed 1

	# Wait for the traffic to queue up
	while not traffic.isInStandstill()
		traffic.step 1/60

	scene.onTickHandled ~>
		return if scene.player.physical.position.z < goalDistance
		@let \done, passed: true, outro:
			title: L "Passed!"
			content: L """
				Your consumption was #{consumption.avgLitersPer100km!.toFixed 2} l/100km.
				"""


	@let \scene, scene
	yield @get \run
	yield P.delay 1000
	yield startLight.switchToGreen()
	startTime = scene.time

	return yield @get \done


export blindFollowInTraffic = seqr.bind (env) ->*
	base = followInTraffic env

	intro = yield base.get \intro
	@let \intro,
		title: L "Anticipating supermiler"
		content: L """
			<p>Drive in the traffic trying to get as much mileage as you
			can.
			
			<p>Note that closer you drive to vehicle before you, the less fuel
			you consume due to the lesser air resistance. But you waste good momentum
			by braking, so try to find a balance where you can keep a short
			headway without having to brake too much.

			<p>Drive in the traffic trying to get as much mileage as you
			can. Best strategy is to have minimum distance to the leading
			vehicle, but avoiding abrupt brakings and accelerations.

			<p>There are no speed limits in this task.

			<p>In this task also your level of anticipation is measured by
			the number of glances you have to take. To briefly see the road,
			press the left lever. Try to accomplish the task as well as you can,
			while taking as few glances as you can.
			"""

	scene = yield base.get \scene
	scene.draftIndicator.el.hide()
	addBlinderTask scene, env
	@let \scene, scene

	yield @get \run
	base.let \run

	result = yield base.get \done

	@let \done, result

	return result

export participantInformation = seqr.bind (env) ->*
	yield ui.inputDialog env, ->
		@ \title .text L "Welcome to the experiment"
		@ \text .text L "Please type your name."
		textbox = $('<input name="name" type="text" style="color: black">')
		.appendTo @ \content
		setTimeout textbox~focus, 0
