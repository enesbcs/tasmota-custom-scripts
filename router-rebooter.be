import string
import json

var PING_IP1 = '8.8.8.8'
var PING_IP2 = '1.1.1.1'
var PING_IP3 = '192.168.0.254'
var PRESULTS  = [0,0,0]
var ASTATE = 0
var STATE_GRACE = 1
var STATE_WAIT  = 2
var STATE_CHECKING = 3
var RELAY_PWR = 1
var SW_MOTION = 2
var RELAY_DISPLAY = 3
var START_TIME = 0
var GRACE_TIME = 90000   #90sec
var WAIT_TIME_DEFAULT = 60000 # 60sec
var WAIT_TIME_MAX = 10800000 # 3hour
var WAIT_TIME         = WAIT_TIME_DEFAULT
var DISPLAY_OFF_TIME   = 900000  #15min
var _motion_lasttime   = tasmota.millis()
var _last_waitstart    = tasmota.millis()

var zaddr = "192.168.0.10" #Zabbix server IP
var zport = 10051 # Zabbix server port
var unitname = ""
var zheader = bytes().fromstring("ZBXD") + bytes("010000000000000000")

lv.start()
scr = lv.scr_act()
scr.clean() 
fs = lv.montserrat_font(14)
fm = lv.montserrat_font(20)
sip = lv.label(scr)
spt1 = lv.label(scr)
spt2 = lv.label(scr)
sstat = lv.label(scr)

def display_init()
 sip.set_style_text_font(fs, lv.PART_MAIN | lv.STATE_DEFAULT)
 sip.set_style_text_color(lv.color_hex(0xffffff), lv.PART_MAIN | lv.STATE_DEFAULT)
 sip.set_text("000.000.000.000")
 sip.align(lv.ALIGN_TOP_LEFT,1,1)
 spt1.set_style_text_font(fs, lv.PART_MAIN | lv.STATE_DEFAULT)
 spt1.set_style_text_color(lv.color_hex(0xffffff), lv.PART_MAIN | lv.STATE_DEFAULT)
 spt1.set_text("000.000.000.000 FAILED")
 spt1.align(lv.ALIGN_TOP_LEFT,1,15)
 spt2.set_style_text_font(fs, lv.PART_MAIN | lv.STATE_DEFAULT)
 spt2.set_style_text_color(lv.color_hex(0xffffff), lv.PART_MAIN | lv.STATE_DEFAULT)
 spt2.set_text("000.000.000.000 FAILED")
 spt2.align(lv.ALIGN_TOP_LEFT,1,29)
 sstat.set_style_text_font(fs, lv.PART_MAIN | lv.STATE_DEFAULT)
 sstat.set_style_text_color(lv.color_hex(0xffffff), lv.PART_MAIN | lv.STATE_DEFAULT)
 sstat.set_text("GRACE")
 sstat.align(lv.ALIGN_TOP_LEFT,1,44)
end

def getip()
    var ip = ""
    var ni = tasmota.eth()
    if ni.has('ip')
       ip = ni['ip']
    end
    if ip == "" || ip == '0.0.0.0'
       ni = tasmota.wifi()
       if ni.has('ip')
        ip = ni['ip']
       end
    end
    return ip
end

def refresher()
 sip.set_text( getip() )
 var ds1 =""
 var ds2 =""
 if ASTATE == STATE_CHECKING || ASTATE == STATE_WAIT
  ds1 = PING_IP1
  if PRESULTS[0] == 1
   ds1 = ds1 + " OK"
  elif PRESULTS[1] == 1
   ds1 = PING_IP2 + " OK"
  else
   ds1 = PING_IP1 + " FAIL"
  end
  
  ds2 = PING_IP3
  if PRESULTS[2] == 1
   ds2 = ds2 + " OK"
  else
   ds2 = ds2 + " FAIL"
  end
  
 else
  ds1 = ""
  ds2 = ""
 end
 spt1.set_text( ds1 )
 spt2.set_text( ds2 )
 var ns = ""
 if ASTATE == STATE_GRACE
   ns = int((START_TIME+GRACE_TIME-tasmota.millis()) / 1000)
   sstat.set_text( "GRACE "+str(ns)+"s")  
   if ns < -1
     _last_waitstart = tasmota.millis()
     ASTATE = STATE_WAIT
   end
 elif ASTATE == STATE_CHECKING
   sstat.set_text( "CHECKING")
 elif ASTATE == STATE_WAIT
   ns = int((_last_waitstart+WAIT_TIME-tasmota.millis()) / 1000)
   sstat.set_text( "WAIT "+str(ns)+"s")
   if ns < -1
     ASTATE = STATE_CHECKING
   end
 end
end

def ping_reply(value, trigger)
 if ASTATE != STATE_CHECKING
    ASTATE = STATE_CHECKING
    refresher()
 end
 try
  var reach = 0
  if value['Reachable'] == true
   reach = 1
  end
  if value['IP'] == PING_IP1
   PRESULTS[0] = reach     
  elif value['IP'] == PING_IP2
   PRESULTS[1] = reach
  elif value['IP'] == PING_IP3
   PRESULTS[2] = reach  
  end
 except .. as e, v
  print(e,v)
 end
end

def motion_change(value, trigger)
    _motion_lasttime = tasmota.millis()
    if value
       if tasmota.get_power(RELAY_DISPLAY-1)==false
          tasmota.set_power(RELAY_DISPLAY-1,true)
       end  
       refresher()
    end
end

def check_ping()
 tasmota.cmd('backlog ping1 '+PING_IP1+';ping1 '+PING_IP3)
 if PRESULTS[0] == 0
    tasmota.cmd('ping1 '+PING_IP2)
 end 
end

def bgproc()
 if tasmota.get_power(RELAY_DISPLAY-1) && DISPLAY_OFF_TIME>0
      if tasmota.time_reached(_motion_lasttime+DISPLAY_OFF_TIME)
       tasmota.set_power(RELAY_DISPLAY-1,false)
      end
 end
 if ASTATE == STATE_GRACE
   if tasmota.time_reached(START_TIME+GRACE_TIME)
    check_ping()
    refresher()
   end
 elif ASTATE == STATE_WAIT
   if tasmota.time_reached(_last_waitstart+WAIT_TIME)
    ASTATE = STATE_CHECKING
    refresher()
   end
 elif ASTATE == STATE_CHECKING
  if PRESULTS[0] == 0 && PRESULTS[1] == 0
     WAIT_TIME = WAIT_TIME * 2
     if WAIT_TIME > WAIT_TIME_MAX
       WAIT_TIME = WAIT_TIME_DEFAULT
     end
     tasmota.set_power(RELAY_PWR-1,true)
     _last_waitstart = tasmota.millis()
     ASTATE = STATE_WAIT
     refresher()
  else
     if WAIT_TIME > WAIT_TIME_DEFAULT
        WAIT_TIME = WAIT_TIME_DEFAULT
        refresher()
     end
  end
 end
end

def bgpinger()
 if ASTATE == STATE_CHECKING
  check_ping()
 end
end

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
   if unitname == ''
    res = tasmota.cmd("DeviceName")
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
 if ASTATE == STATE_CHECKING
  try
   sendzabbix(zabbixstruct())
  except .. as e, v
   print(e,v)
  end
 end
end

ASTATE = STATE_GRACE
START_TIME = tasmota.millis()
tasmota.cmd("backlog PowerOnState 0;Power1 0;pulsetime1 50;wifi 0")
tasmota.set_power(RELAY_DISPLAY-1,true)
display_init()
refresher()
tasmota.add_rule("Ping#?", ping_reply)
tasmota.add_cron("*/2 * * * * *", bgproc, "bgproc")
tasmota.add_cron("*/5 * * * * *", bgpinger, "bgpinger")
tasmota.add_cron("*/10 * * * * *", refresher, "refresher")
tasmota.add_rule(string.format('Switch%d#State',SW_MOTION),motion_change)
tasmota.add_rule(string.format('Power%d#State',SW_MOTION),motion_change)
tasmota.add_cron("0 */15 * * * *", reporttele, "every_15_m")
