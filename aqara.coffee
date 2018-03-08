module.exports = (env) ->

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = env.require 'events'
  LumiAqara = require './lumi-aqara'

  class Board extends events.EventEmitter

    constructor: (framework, config) ->
      @config = config
      @framework = framework

      @driver = new LumiAqara()

      env.logger.debug("Searching for gateway...")
      @driver.on('gateway', (gateway) =>
        env.logger.debug("Gateway discovered")

        # Gateway ready
        gateway.on('ready', () =>
          env.logger.debug('Gateway is ready')
          gateway.setPassword(@config.password)
        )

        # Gateway offline
        gateway.on('offline', () =>
          env.logger.debug('Gateway is offline')
        )

        gateway.on('subdevice', (device) =>
          env.logger.debug(device)
          switch device.getType()
            when 'magnet'
              device.on('open', () =>
                @emit "magnet", device
              )
              device.on('close', () =>
                @emit "magnet", device
              )
            when 'motion'
              device.on('motion', () =>
                @emit "motion", device
              )
              device.on('noMotion', () =>
                @emit "motion", device
              )
            when 'leak'
              device.on('update', () =>
                @emit "leak", device
              )
            when 'sensor'
              device.on('update', () =>
                @emit "sensor", device
              )
            when 'cube'
              device.on('update', () =>
                @emit "cube", device
              )
            when 'switch'
              device.on('click', () =>
                @emit "switch", device
              )
              device.on('doubleClick', () =>
                @emit "switch", device
              )
              device.on('longClickPress', () =>
                @emit "switch", device
              )
              device.on('longClickRelease', () =>
                @emit "switch", device
              )
        )
      )

  Promise.promisifyAll(Board.prototype)

  class aqara extends env.plugins.Plugin

    init: (app, @framework, @config) =>

      @board = new Board(@framework, @config)

      #Register devices
      deviceConfigDef = require("./device-config-schema.coffee")

      deviceClasses = [
        AqaraMotionSensor,
        AqaraDoorSensor,
        AqaraLeakSensor
      ]

      for Cl in deviceClasses
        do (Cl) =>
          @framework.deviceManager.registerDeviceClass(Cl.name, {
            configDef: deviceConfigDef[Cl.name]
            createCallback: (config,lastState) =>
              device  =  new Cl(config,lastState, @board)
              return device
          })

  class AqaraMotionSensor extends env.devices.PresenceSensor

    constructor: (@config, lastState, @board) ->
      @id = @config.id
      @name = @config.name
      @_presence = lastState?.presence?.value or false
      @_battery = lastState?.battery?.value
      @_lux = lastState?.lux?.value

      @addAttribute('battery', {
        description: "Battery",
        type: "number"
        displaySparkline: false
        unit: "%"
        icon:
          noText: true
          mapping: {
            'icon-battery-empty': 0
            'icon-battery-fuel-1': [0, 20]
            'icon-battery-fuel-2': [20, 40]
            'icon-battery-fuel-3': [40, 60]
            'icon-battery-fuel-4': [60, 80]
            'icon-battery-fuel-5': [80, 100]
            'icon-battery-filled': 100
          }
      })
      @['battery'] = ()-> Promise.resolve(@_battery)

      @addAttribute('lux', {
        description: "Lux",
        type: "number"
        displaySparkline: false
        unit: "lux"
      })
      @['lux'] = ()-> Promise.resolve(@_lux)

      resetPresence = ( =>
        @_setPresence(no)
      )

      @rfValueEventHandler = ( (result) =>
        env.logger.info(result)
        if result.getSid() is @config.SID
          @_setPresence(result._motion)
          clearTimeout(@_resetPresenceTimeout)
          @_resetPresenceTimeout = setTimeout(resetPresence, @config.resetTime)

          @_lux = parseInt(result.getLux())
          @emit "lux", @_lux

          @_battery = result.getBatteryPercentage()
          @emit "battery", @_battery
      )

      @board.on("motion", @rfValueEventHandler)

      super()

    destroy: ->
      clearTimeout(@_resetPresenceTimeout)
      @board.removeListener "motion", @rfValueEventHandler
      super()

    getPresence: -> Promise.resolve @_presence
    getBattery: -> Promise.resolve @_battery
    getLux: -> Promise.resolve @_lux


  class AqaraDoorSensor extends env.devices.ContactSensor

    constructor: (@config, lastState, @board) ->
      @id = @config.id
      @name = @config.name
      @_contact = lastState?.contact?.value or false
      @_battery = lastState?.battery?.value

      @addAttribute('battery', {
        description: "Battery",
        type: "number"
        displaySparkline: false
        unit: "%"
        icon:
          noText: true
          mapping: {
            'icon-battery-empty': 0
            'icon-battery-fuel-1': [0, 20]
            'icon-battery-fuel-2': [20, 40]
            'icon-battery-fuel-3': [40, 60]
            'icon-battery-fuel-4': [60, 80]
            'icon-battery-fuel-5': [80, 100]
            'icon-battery-filled': 100
          }
      })
      @['battery'] = ()-> Promise.resolve(@_battery)

      @rfValueEventHandler = ( (result) =>
        env.logger.info(result)
        if result.getSid() is @config.SID
          @_setContact(result.isOpen())
          @_battery = result.getBatteryPercentage()
          @emit "battery", @_battery
      )

      @board.on("magnet", @rfValueEventHandler)

      super()

    destroy: ->
      @board.removeListener "leak", @rfValueEventHandler
      super()

    getContact: -> Promise.resolve @_contact
    getBattery: -> Promise.resolve @_battery

  class AqaraLeakSensor extends env.devices.PresenceSensor

    constructor: (@config, lastState, @board) ->
      @id = @config.id
      @name = @config.name
      @_presence = lastState?.presence?.value or false
      @_battery = lastState?.battery?.value

      @addAttribute('battery', {
        description: "Battery",
        type: "number"
        displaySparkline: false
        unit: "%"
        icon:
          noText: true
          mapping: {
            'icon-battery-empty': 0
            'icon-battery-fuel-1': [0, 20]
            'icon-battery-fuel-2': [20, 40]
            'icon-battery-fuel-3': [40, 60]
            'icon-battery-fuel-4': [60, 80]
            'icon-battery-fuel-5': [80, 100]
            'icon-battery-filled': 100
          }
      })
      @['battery'] = ()-> Promise.resolve(@_battery)

      @rfValueEventHandler = ( (result) =>
        env.logger.info(result)
        if result.getSid() is @config.SID
          @_setPresence(result.isLeaking())
          @_battery = result.getBatteryPercentage()
          @emit "battery", @_battery
      )

      @board.on("leak", @rfValueEventHandler)

      super()

    destroy: ->
      @board.removeListener "leak", @rfValueEventHandler
      super()

    getPresence: -> Promise.resolve @_presence
    getBattery: -> Promise.resolve @_battery


  aqara = new aqara

  return aqara