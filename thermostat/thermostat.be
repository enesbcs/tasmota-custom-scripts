import string
import json
import mqtt
import webserver
import persist 

var homeronev     = 'HTU21'
var ROT_STEP      = 0.25
var ROT_MIN       = 5
var ROT_MAX       = 30
var RELAY_HEATING = 1
var SW_MOTION     = 2
var RELAY_DISPLAY = 3
var SETPOINT      = 0
var HYSTERESIS    = 0.3
var bgcolor       = lv.color_hex(0x000000)
var HEAT_MAX_TIME      = 1800000 #30min
var HEAT_MIN_TIME      = 30000   #30sec
var HEAT_COOLDOWN_TIME = 300000  #5min
var DISPLAY_OFF_TIME   = 900000  #15min
var EXT_TEMP_TIMEOUT   = 120000  #2min
var DISCOVERY_PREFIX   = "homeassistant"
var unitname = ""
var teletopic = ""
var stattopic = ""
var cmdtopic = ""

var ACT_TEMP      = 99
var EXT_TEMP      = 99
var ATEMP         = 99
var _ext_temp_lasttime = 0
var _motion_lasttime   = tasmota.millis()
var MASTER_DISABLED    = 0
var HEATING_ACTIVE     = false
var _heat_time_started = 0
var _heat_time_stopped = 0

lv.start()
scr = lv.scr_act()
scr.clean() 
fs = lv.montserrat_font(20)
fm = lv.montserrat_font(28)
arc = lv.arc(scr)
stemp1 = lv.label(scr)
stemp2 = lv.label(scr)
ttemp = lv.label(scr)
theating = lv.label(scr)

def getmac(cter)
    var mac = ""
    var ni = tasmota.eth()
    if ni.has('mac')
       mac = ni['mac']
    end
    if mac == ""
       ni = tasmota.wifi()
       if ni.has('mac')
        mac = ni['mac']
       end
    end
    mac = string.replace(mac,":","")
    if cter>0
       var slen = size(mac)
       if slen>cter
        mac = mac[(slen-cter)..(slen-1)]
       end
    end
    return mac
end

def gettemp()
 try
  var sensors=json.load(tasmota.read_sensors())
  return number(sensors[homeronev]['Temperature'])
 except .. as e, v
  print(homeronev, "temp sensor unavailable!")
  return 99
 end
end

def display_init()
 scr.set_style_bg_color(bgcolor, lv.PART_MAIN | lv.STATE_DEFAULT)
 arc.set_end_angle(200)
 arc.set_size(100, 100)
 arc.set_range(ROT_MIN,ROT_MAX)
 arc.set_value(int(ROT_MIN))
 arc.align(lv.ALIGN_TOP_MID,0,3)
 stemp1.set_style_text_font(fs, lv.PART_MAIN | lv.STATE_DEFAULT)
 stemp1.set_style_text_color(lv.color_hex(0xffffff), lv.PART_MAIN | lv.STATE_DEFAULT)
 stemp1.set_text("00.0 C")
 stemp1.align(lv.ALIGN_BOTTOM_LEFT,0,0)
 stemp2.set_style_text_font(fs, lv.PART_MAIN | lv.STATE_DEFAULT)
 stemp2.set_style_text_color(lv.color_hex(0xffffff), lv.PART_MAIN | lv.STATE_DEFAULT)
 stemp2.set_text("00.0 C")
 stemp2.align(lv.ALIGN_BOTTOM_RIGHT,0,0)
 ttemp.set_style_text_font(fm, lv.PART_MAIN | lv.STATE_DEFAULT)
 ttemp.set_style_text_color(lv.color_hex(0xffffff), lv.PART_MAIN | lv.STATE_DEFAULT)
 ttemp.set_text("00.0\nC")
 ttemp.set_style_text_align(lv.TEXT_ALIGN_CENTER, lv.PART_MAIN) 
 ttemp.align(lv.ALIGN_CENTER, 0, 0)
 theating.set_style_text_font(fs, lv.PART_MAIN | lv.STATE_DEFAULT)
 theating.set_style_text_color(bgcolor, lv.PART_MAIN | lv.STATE_DEFAULT)
 theating.set_text(lv.SYMBOL_CHARGE)
 theating.align(lv.ALIGN_BOTTOM_MID, 0, -15)
 lv.scr_load(scr)
end

def set_setpoint(settemp)
    try
     SETPOINT = number(settemp)
     ttemp.set_text( string.format('%2.1f\nC',SETPOINT) )
     arc.set_value(int(SETPOINT))
     mqtt.publish(stattopic+"thermostat/target_t",string.format('%2.1f',SETPOINT))
    except .. as e, v
     return false
    end
end

def rotary_inp(value, trigger)
  try
   var sp = 0
   if value == 0
      sp = SETPOINT - ROT_STEP
   else
      sp = SETPOINT + ROT_STEP
   end
   if sp<ROT_MIN
      sp=ROT_MIN
   else
    if sp>ROT_MAX
      sp=ROT_MAX
    end
   end
   set_setpoint(sp)
   _motion_lasttime = tasmota.millis()
  except .. as e, v
   print('catch execption:', str(e) + ' >>>\n    ' + str(v))
  end
end

def set_acttemp(tempid, temp)
   var _atemp = number(temp)
   if tempid==1
     stemp1.set_text( string.format('%2.1f C',_atemp) )
     stemp1.set_style_text_color(lv.color_hex(0xffffff), lv.PART_MAIN | lv.STATE_DEFAULT)
     stemp2.set_style_text_color(bgcolor, lv.PART_MAIN | lv.STATE_DEFAULT)
     mqtt.publish(stattopic+"thermostat/tmp",string.format('%2.1f',_atemp))
   else
     stemp2.set_text( string.format('%2.1f C',_atemp) )
     stemp2.set_style_text_color(lv.color_hex(0xffffff), lv.PART_MAIN | lv.STATE_DEFAULT)
     stemp1.set_style_text_color(bgcolor, lv.PART_MAIN | lv.STATE_DEFAULT)   
     _ext_temp_lasttime = tasmota.millis()
     EXT_TEMP = _atemp
     mqtt.publish(stattopic+"thermostat/ext_tmp",string.format('%2.1f',_atemp))
   end
   ATEMP = _atemp
   mqtt.publish(stattopic+"thermostat/target_t",string.format('%2.1f',SETPOINT))
end

def set_heating(onoff)
  if HEATING_ACTIVE != tasmota.get_power(RELAY_HEATING-1)
     HEATING_ACTIVE = tasmota.get_power(RELAY_HEATING-1)
  end
  if HEATING_ACTIVE != onoff
   tasmota.set_power(RELAY_HEATING-1,onoff)
  end
end

def heatdisplay(onoff)
 if onoff
  theating.set_style_text_color(lv.color_hex(0xff0000), lv.PART_MAIN | lv.STATE_DEFAULT)
  _heat_time_started = tasmota.millis()
 else
  theating.set_style_text_color(bgcolor, lv.PART_MAIN | lv.STATE_DEFAULT)
  _heat_time_started = 0
  if tasmota.time_reached(HEAT_COOLDOWN_TIME)
     _heat_time_stopped = tasmota.millis()
  end
 end
 HEATING_ACTIVE = onoff
end

def heat_change(value, trigger)
    heatdisplay(value)
end

def motion_change(value, trigger)
    if value
       if tasmota.get_power(RELAY_DISPLAY-1)==false
          _motion_lasttime = tasmota.millis()
          tasmota.set_power(RELAY_DISPLAY-1,true)
       end       
    else
       _motion_lasttime = tasmota.millis()
    end
end

def bgproc()
    if tasmota.get_power(RELAY_DISPLAY-1) && DISPLAY_OFF_TIME>0
      if tasmota.time_reached(_motion_lasttime+DISPLAY_OFF_TIME)
       tasmota.set_power(RELAY_DISPLAY-1,false)
      end
    end
    if MASTER_DISABLED==1
       if HEATING_ACTIVE
        set_heating(false)
       end
       return true
    end
    if HEATING_ACTIVE
     if _heat_time_started>0 && HEAT_MAX_TIME>0 && tasmota.time_reached(_heat_time_started+HEAT_MAX_TIME)
        set_heating(false)
        return true
     end
     if ATEMP >= (SETPOINT + HYSTERESIS)
        if HEAT_MIN_TIME>0 && tasmota.time_reached(_heat_time_started+HEAT_MIN_TIME)==false
         return true
        end
        set_heating(false)
     end
    else
     if ATEMP < SETPOINT
      if _heat_time_stopped>0 && HEAT_COOLDOWN_TIME>0 && tasmota.time_reached(_heat_time_stopped+HEAT_COOLDOWN_TIME)==false
        return false
      end
      set_heating(true)
     end
    end
end

def bgsensors()
    ACT_TEMP = gettemp()
    if ACT_TEMP<99
      if _ext_temp_lasttime<1 || tasmota.time_reached(_ext_temp_lasttime+EXT_TEMP_TIMEOUT)
       set_acttemp(1,ACT_TEMP)
      end
    end
    var psp = persist.find('setpoint',-1)
    if psp != SETPOINT && SETPOINT >= ROT_MIN && SETPOINT <= ROT_MAX
          persist.setpoint = SETPOINT
          persist.save()
    end
end

def mqtt_cmds(topic, idx, payload_s, payload_b)
  if string.find(topic,"target_t")>=0
     set_setpoint(payload_s)  
  elif string.find(topic,"ext_tmp")>=0
     set_acttemp(2,payload_s)
  elif string.find(topic,"disabled")>=0
     if string.find(payload_s,"ON")>=0 || string.find(payload_s,"1")>=0
       MASTER_DISABLED = 1
     else
       MASTER_DISABLED = 0
     end
     mqtt.publish(stattopic+"thermostat/disabled",str(MASTER_DISABLED))
  end
  return true
end

def webhandler()
    try
      if webserver.has_arg("cmd")
       var cmds = string.split(str(webserver.arg("cmd")),',')
       if cmds[0] == 'thermo'
          if cmds[1] == 'setpoint'
             set_setpoint(number(cmds[2]))
          elif cmds[1] == 'mode'
             var dis = 0
             if number(cmds[2]) == 0
                dis = 1
             end
             MASTER_DISABLED = dis
             mqtt.publish(stattopic+"thermostat/disabled",str(MASTER_DISABLED))
          elif cmds[1] == 'exttemp'
             set_acttemp(2,number(cmds[2]))
          end
       end
      end
      webserver.content_stop()    
    except .. as e, m
      print(format("BRY: Exception> '%s' - %s", e, m))
    end
end

def filltemplates(tname, trelnum, templ)
  var tstr = string.replace(string.replace(templ,"%name%",str(tname)),"%relnum%",str(trelnum))
  tstr = string.replace(string.replace(tstr,"%discovery_prefix%",DISCOVERY_PREFIX),"%tasmota_mac%",getmac(6))
  tstr = string.replace(string.replace(tstr,"%tasmota_id%",unitname),"%teletopic%",teletopic)
  tstr = string.replace(string.replace(tstr,"%cmdtopic%",cmdtopic),"%stattopic%",stattopic)
  return tstr  
end

def subscribes()
  unitname = string.replace(tasmota.cmd('Topic')['Topic'],"%06X",getmac(6))
  teletopic = string.replace(string.replace(tasmota.cmd('FullTopic')['FullTopic'], '%topic%', unitname), '%prefix%', tasmota.cmd('Prefix')['Prefix3'])
  stattopic = string.replace(string.replace(tasmota.cmd('FullTopic')['FullTopic'], '%topic%', unitname), '%prefix%', tasmota.cmd('Prefix')['Prefix2'])
  cmdtopic = string.replace(string.replace(tasmota.cmd('FullTopic')['FullTopic'], '%topic%', unitname), '%prefix%', tasmota.cmd('Prefix')['Prefix1'])
  print("Subscribed to",cmdtopic+"thermostat")
  mqtt.subscribe(cmdtopic+"thermostat/#", mqtt_cmds)
  if DISCOVERY_PREFIX != ""
     try
       var dtopic = filltemplates("Heating", RELAY_HEATING, '%discovery_prefix%/switch/%tasmota_mac%_RL_%relnum%/config')
       var dpl = filltemplates("Heating", RELAY_HEATING, '{"name": "%tasmota_id% %name%","stat_t": "%stattopic%POWER%relnum%","avty_t": "%teletopic%LWT","pl_avail": "Online","pl_not_avail": "Offline","cmd_t": "%cmdtopic%POWER%relnum%","pl_off": "OFF","pl_on": "ON","uniq_id": "%tasmota_mac%_RL_%relnum%","dev": {"ids": ["%tasmota_mac%"]}}')
       mqtt.publish(dtopic,dpl,true)
       dtopic = filltemplates("Display", RELAY_DISPLAY,'%discovery_prefix%/switch/%tasmota_mac%_RL_%relnum%/config')
       dpl = filltemplates("Display", RELAY_DISPLAY,'{"name": "%tasmota_id% %name%","stat_t": "%stattopic%POWER%relnum%","avty_t": "%teletopic%LWT","pl_avail": "Online","pl_not_avail": "Offline","cmd_t": "%cmdtopic%POWER%relnum%","pl_off": "OFF","pl_on": "ON","uniq_id": "%tasmota_mac%_RL_%relnum%","dev": {"ids": ["%tasmota_mac%"]}}')
       mqtt.publish(dtopic,dpl,true)
       dtopic = filltemplates("Motion", SW_MOTION,'%discovery_prefix%/binary_sensor/%tasmota_mac%_RL_%relnum%/config')
       dpl = filltemplates("Motion", SW_MOTION,'{"name": "%tasmota_id% %name%","stat_t": "%stattopic%POWER%relnum%","avty_t": "%teletopic%LWT","pl_avail": "Online","pl_not_avail": "Offline","pl_off": "OFF","pl_on": "ON","uniq_id": "%tasmota_mac%_RL_%relnum%","dev": {"ids": ["%tasmota_mac%"]}}')
       mqtt.publish(dtopic,dpl,true)
       dtopic = filltemplates("Online", "",'%discovery_prefix%/binary_sensor/%tasmota_mac%_online/config')
       dpl = filltemplates("Online", "",'{"name": "%tasmota_id% %name%","stat_t": "%teletopic%LWT","pl_on": "Online","pl_off": "Offline","uniq_id": "%tasmota_mac%_online","dev": {"ids":["%tasmota_mac%"]}}')
       mqtt.publish(dtopic,dpl,true)
       dtopic = filltemplates("Thermostat master disable","",'%discovery_prefix%/switch/%tasmota_mac%_disable/config')
       dpl = filltemplates("Thermostat master disable","",'{"name": "%tasmota_id% %name%","stat_t":"%stattopic%thermostat/disabled","avty_t": "%teletopic%LWT","pl_avail": "Online","pl_not_avail": "Offline","cmd_t": "%cmdtopic%thermostat/disabled","pl_off": "0","pl_on": "1","uniq_id": "%tasmota_mac%_thermostat_disabled","dev": {"ids": ["%tasmota_mac%"]}}')
       mqtt.publish(dtopic,dpl,true)
       dtopic = filltemplates("Thermostat","",'%discovery_prefix%/climate/%tasmota_mac%_thermostat/config')
       dpl = filltemplates("Thermostat","",'{"name": "%tasmota_id% %name%","temperature_command_topic": "%cmdtopic%thermostat/target_t","temperature_state_topic": "%stattopic%thermostat/target_t","current_temperature_topic": "%stattopic%thermostat/tmp","temperature_unit": "C","precision": 0.1,"temp_step": 0.5,"max_temp": 30,"min_temp": 5,"icon": "mdi:thermostat","uniq_id": "%tasmota_mac%_thermostat","dev": {"ids": ["%tasmota_mac%"]}}')
       mqtt.publish(dtopic,dpl,true)
       dtopic = filltemplates("External temperature sensor","",'%discovery_prefix%/climate/%tasmota_mac%_ext_temp/config')
       dpl = filltemplates("External temperature sensor","",'{"name": "%tasmota_id% %name%","temperature_command_topic": "%cmdtopic%thermostat/ext_tmp","temperature_state_topic": "%stattopic%thermostat/ext_tmp","temperature_unit": "C","precision": 0.1,"temp_step": 0.1,"max_temp": 50,"min_temp": 0,"uniq_id": "%tasmota_mac%_ext_tmp"}')
       mqtt.publish(dtopic,dpl,true)
     except .. as e, v
      print(str(e),str(v))
     end
  end
  mqtt.publish(stattopic+"thermostat/disabled",str(MASTER_DISABLED))
  webserver.on("/control", / -> webhandler(), webserver.HTTP_GET)
  if ATEMP>98 && ACT_TEMP>98
   set_heating(false)
   _heat_time_stopped = 0
  end
end

if persist.has('setpoint')
   SETPOINT = persist.find('setpoint')
end
tasmota.cmd("BackLog SetOption43 1;SetOption98 1;SetOption1 1;SetOption36 5;WebButton1 Heating;WebButton2 Motion;WebButton3 Display;Teleperiod 60;")
swstr = "BackLog " + string.format('SwitchMode%d 3;',RELAY_HEATING)
swstr = swstr + string.format('SwitchMode%d 1;',SW_MOTION)
swstr = swstr + string.format('SwitchMode%d 1;',RELAY_DISPLAY)
tasmota.cmd(swstr)
display_init()
tasmota.set_power(RELAY_DISPLAY-1,true)
set_setpoint(SETPOINT)
tasmota.add_rule(string.format('Switch%d#State',RELAY_HEATING),heat_change)
tasmota.add_rule(string.format('Power%d#State',RELAY_HEATING),heat_change)
tasmota.add_rule(string.format('Switch%d#State',SW_MOTION),motion_change)
tasmota.add_rule(string.format('Power%d#State',SW_MOTION),motion_change)
tasmota.add_rule("Rotary1#Pos1",rotary_inp)
tasmota.add_cron("*/1 * * * * *", bgproc, "bgproc")
tasmota.add_cron("1 * * * * *", bgsensors, "bgsensors")
if mqtt.connected
   subscribes()
else
   tasmota.add_rule("MQTT#Connected=1", subscribes)
end
