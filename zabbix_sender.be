import json

var zaddr = "192.168.1.1" #Zabbix server IP
var zport = 10051 # Zabbix server port
var unitname = "" # leave it empty to use tasmota name, or set it here

var zheader = bytes().fromstring("ZBXD") + bytes("010000000000000000")

def sendzabbix(data)
 var tcp = tcpclient()
 tcp.connect(zaddr, zport)
 if tcp.connected()
  tcp.write(data)
 end
 tcp.close()
end

def dataentry(hname, zkey, zval)
    var de = {}
    de["host"] = hname
    de["key"] = zkey
    de["value"] = zval
    return de
end

def gettelemetry()
   var ressen = {}
   var res
   var hostname = ""
   ressen['request'] = 'sender data'
   ressen['data'] = []
   res = tasmota.cmd("DeviceName")
   if unitname == ''
    if res != nil && type(res) == 'instance'
     if (res.find("DeviceName", {}) )
      hostname = res['DeviceName']
     end
    end
   else
    hostname = unitname
   end
   if hostname == ''
      print("Hostname not found!")
      return ""
   end
   var sensors = json.load(tasmota.read_sensors())
   if sensors != nil && type(sensors) == 'instance'
    for entry: sensors.keys() #check all entry in sensor data
      if type(sensors[entry]) == 'instance' #if instance list all subvalues
         for subentry: sensors[entry].keys()
             ressen['data'].push(dataentry(hostname,entry+'-'+subentry,sensors[entry][subentry]))
         end
      end
    end
   end
   res = tasmota.memory()
   if res != nil
      ressen['data'].push(dataentry(hostname,'tasmota-heapfree',res['heap_free']))
   end
   res = tasmota.wifi()
   if res != nil
      if res['up'] != false
       ressen['data'].push(dataentry(hostname,'tasmota-rssi',res['rssi']))
      else
       ressen['data'].push(dataentry(hostname,'tasmota-rssi',-100))
      end
   end
   res = tasmota.cmd("status 1")
   if res != nil && type(res) == 'instance'
     if (res.find("StatusPRM", {}) )
      ressen['data'].push(dataentry(hostname,'tasmota-uptime',res['StatusPRM']['Uptime']))
     end
   end
   return json.dump(ressen)
end

def zabbixstruct()
    var datas = bytes().fromstring(gettelemetry())
    var dlen = size(datas)
    zheader[5] = int(dlen % 256)
    zheader[6] = int(dlen / 256)
    datas = zheader + datas
    return datas
end

def reporttele()
  try
   sendzabbix(zabbixstruct())
  except .. as e, v
   print(e,v)
  end
end

tasmota.add_cron("0 */15 * * * *", reporttele, "every_15_m")
