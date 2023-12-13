import json
import string

# Add your Thingsboard server URL (http/https)
var tburl = 'http://demo.thingsboard.io'
# Create a device in Thingsboard generate an AccessToken and specify here
var accesstoken = 'l14atfxyzt7fry44atgx'

def callweb(url, payload)
 var cl = webclient()
 cl.begin(url)
 cl.add_header('Content-Type','application/json')
 var r = cl.POST(payload)
 if r != 200
  print("HTTP error",r,url,payload)
 end
 cl.close()
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
 return json.dump(ressen)
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
 var repurl = tburl + '/api/v1/' + accesstoken + '/telemetry'
 print("Sending sensor data")
 callweb(repurl,getsensors())
end

def reporttele()
 var repurl = tburl + '/api/v1/' + accesstoken + '/telemetry'
 print("Sending hw telemetry")
 callweb(repurl,gettelemetry())
end

tasmota.add_cron("0 */2 * * * *", reportsensor, "every_2_m")
tasmota.add_cron("0 */30 * * * *", reporttele, "every_30_m")
reporttele()
