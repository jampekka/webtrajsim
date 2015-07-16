P = require 'bluebird'
$ = require 'jquery'
{Signal} = require './signal.ls'

export class WsController
	@Connect = (url) -> new P (resolve, reject) ->
		socket = new WebSocket url
		socket.onopen = ->
			resolve new WsController socket

	(@socket) ->
		@throttle = 0
		@brake = 0
		@steering = 0
		@direction = 1
		@change = new Signal
		@socket.onmessage = (msg) ~>
			event = JSON.parse msg.data
			for key, value of event
				@change.dispatch key, value
			@ <<< event

	set: (obj) ->
		@socket.send JSON.stringify obj

export class KeyboardController
	->
		@throttle = 0
		@brake = 0
		@steering = 0
		@direction = 1

		@throttleTarget = 0
		@brakeTarget = 0
		@steeringLeft = 0
		@steeringRight = 0

		changeSpeed = 2

		nudge = (dt, name, target) ~>
			return if not isFinite dt
			diff = target - @[name]
			change = dt*changeSpeed*Math.sign(diff)
			if diff < 0
				change = Math.max change, diff
			else
				change = Math.min change, diff
			@[name] += change

		prevTime = undefined
		tick = ~>
			time = Date.now()
			dt = (time - prevTime)/1000
			prevTime := time
			nudge dt, \throttle, @throttleTarget
			nudge dt, \brake, @brakeTarget
			nudge dt, \steering, (@steeringLeft - @steeringRight)
			requestAnimationFrame tick
		tick()
		@change = new Signal

		UP = 38
		DOWN = 40
		SPACE = 32
		LEFT = 37
		RIGHT = 39

		$("body")
		.keydown (e) ~>
			switch e.which
			| UP => @throttleTarget = 1
			| DOWN => @brakeTarget = 1
			| LEFT => @steeringLeft = 1
			| RIGHT => @steeringRight = 1
			| SPACE => @_update \blinder, true
		.keyup (e) ~>
			switch e.which
			| UP => @throttleTarget = 0
			| DOWN => @brakeTarget = 0
			| LEFT => @steeringLeft = 0
			| RIGHT => @steeringRight = 0
			| SPACE => @_update \blinder, false



	_update: (key, value) ->
		@change.dispatch key, value
		@[key] = value

	set: ->

export NonSteeringControl = (orig) ->
	ctrl = ^^orig
	ctrl.steering = 0
	return ctrl


