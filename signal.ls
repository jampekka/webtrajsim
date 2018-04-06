export Signal = ({onAdd=->}={}) ->
	listeners = []

	signal = (cb) ->
		return cb if onAdd(cb) === false
		listeners.push cb
		return cb

	signal.add = signal
	signal.dispatch = (...args) !->
		oldListeners = listeners
		listeners := []
		survivors = [.. for oldListeners when (.. ...args) !== false]
		listeners := survivors.concat listeners
	signal.remove = (cb) ->
		listeners := listeners.filter (v) -> v != cb

	signal.destroy = ->
		listeners := []
		signal.dispatch = -> false
	return signal
