import json
import string
import mqtt

# Set Thingsboard MQTT at Tasmota settings before starting this script!
# Create a device in Thingsboard generate ClientID and set it at 'Configure MQTT'
var chan_attrib = 'v1/devices/me/attributes'
var chan_tele   = 'v1/devices/me/telemetry'
var chan_attrib_rpc = 'v1/devices/me/rpc/request/+'

var RELAY_COUNT = tasmota.get_power().size()

def mqtt_cmds(topic, idx, payload_s, payload_b) # Handling incoming RCP request from Thingsboard
  if string.find(payload_s,"{") >= 0
     var pj = json.load(payload_s)
     if pj.find('method') != nil
        var reqname = pj['method']
        var reqstat
        if reqname == 'getGpioStatus'
           reqstat = pj['params']
           if str(reqstat) == '{}'
              if RELAY_COUNT>0
               var reply = {}
               for i:0..RELAY_COUNT-1
                   reply[str(i+1)] = tasmota.get_power(i)
               end
               var reptopic = string.replace(topic,"request","response")
               mqtt.publish(reptopic,json.dump(reply))
              end
           end
           return true
        elif reqname == 'setGpioStatus'
           reqstat = pj['params']
           if reqstat.find('pin') != nil
             tasmota.set_power(number(reqstat['pin'])-1,reqstat['enabled'])
             var reply = {}
             var reptopic = string.replace(topic,"request","response")
             reply[ str(reqstat['pin']) ] = reqstat['enabled']
             mqtt.publish(reptopic,json.dump(reply))
           end
           return true
        end
        var ttaskname = ""
        var valuename = ""
        if string.find(reqname,'-') >= 0
           var ta = string.split(reqname,'-')
           ttaskname = ta[0]
           valuename = ta[1]
        else
           ttaskname = reqname # not an option
           return false
        end
        if pj.find('params') != nil #setvalue
           reqstat = pj['params']
           if ttaskname == 'relay'
            tasmota.set_power(number(valuename)-1,reqstat)
           end
           return true
        else # getvalue
           var reply = tasmota.get_power(number(valuename)-1)
           var reptopic = string.replace(topic,"request","response")
           mqtt.publish(reptopic,reply)
           return true
        end
     end
  end
  return true
end

def rule_inp(value, trigger)
  var rnum = -1
  try
   var i=string.find(trigger,"#")
   if i>1
    rnum = number(trigger[i-1])
   end
  except .. as e, v
   print('catch execption:', str(e) + ' >>>\n    ' + str(v))
  end
  if rnum>=0
   if value == 0
      value = 'false'
   elif value == 1
      value = 'true'
   end
   var resen = '{"relay'+'-'+str(rnum)+'":'+str(value)+'}'
   mqtt.publish(chan_attrib,resen)
  end
  return true
end

def getsensors()
 var sensors = json.load(tasmota.read_sensors())
 var ressen = {}
 if sensors != nil && type(sensors) == 'instance'
  for entry: sensors.keys() #check all entry in sensor data
      if type(sensors[entry]) == 'instance' #if instance list all subvalues
         for subentry: sensors[entry].keys()
             ressen[entry+'-'+subentry] = sensors[entry][subentry]
         end
      end
  end
 end
 if ressen.size()>0
  return json.dump(ressen)
 else
  return nil
 end
end

def getrelays()
    var ressen = {}
    if RELAY_COUNT>0
     for i:0..RELAY_COUNT-1
      ressen['relay-'+str(i+1)] = tasmota.get_power(i)
     end
     return json.dump(ressen)
    end
    return nil
end

def gettelemetry()
   var ressen = {}
   var res
   res = tasmota.memory()
   if res != nil
      ressen['tasmota-heap_free'] = res['heap_free']
      ressen['tasmota-flash'] = res['flash']
   end
   res = tasmota.arch()
   if res != nil && res != ''
      ressen['tasmota-arch'] = res
   end
   res = tasmota.wifi()
   if res != nil
      if res['up'] != false
       ressen['wifi-ip'] = res['ip']
       ressen['wifi-rssi'] = res['rssi']
      else
       ressen['wifi-ip'] = '0.0.0.0'
       ressen['wifi-rssi'] = -100
      end
   end
   res = tasmota.eth()
   if res != nil
      if res['up'] != false
       ressen['eth-ip'] = res['ip']
      else
       ressen['eth-ip'] = '0.0.0.0'
      end
   end
   res = tasmota.cmd("status 1")
   if res != nil && type(res) == 'instance'
     if (res.find("StatusPRM", {}) )
      ressen['tasmota-uptime'] = res['StatusPRM']['Uptime']
     end
   end
   res = tasmota.cmd("status 2")
   if res != nil && type(res) == 'instance'
     if (res.find("StatusFWR", {}) )
      ressen['tasmota-firmware'] = res['StatusFWR']['Version']
     end
   end
   return json.dump(ressen)
end

def reportsensor()
 var gr = getsensors()
 if gr != nil
  mqtt.publish(chan_tele,gr)
 end
 gr = getrelays()
 if gr != nil
  mqtt.publish(chan_attrib,gr)
 end
end

def reporttele()
 mqtt.publish(chan_tele,gettelemetry())
end

def subscribes()
  mqtt.subscribe(chan_attrib_rpc, mqtt_cmds)
  reporttele()
end

if RELAY_COUNT>0
 for i:0..RELAY_COUNT-1
  tasmota.add_rule(string.format('Power%d#State',(i+1)),rule_inp)
 end
end
tasmota.add_cron("0 */2 * * * *", reportsensor, "every_2_m")
tasmota.add_cron("0 */30 * * * *", reporttele, "every_30_m")
if mqtt.connected
   subscribes()
else
   tasmota.add_rule("MQTT#Connected=1", subscribes)
end
