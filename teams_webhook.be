import json
import string

var wurl = 'https://webhook.site/ce7ffa2b-b5af-4233-8884-4163ece1862c'

def callweb(url, text)
 var cl = webclient()
 cl.begin(url)
 cl.add_header('Content-Type','application/json')
 var payload = string.format('{"text": "%s C"}',text)
 var r = cl.POST(payload)
 cl.close()
end

def gettemp()
 var sensors=json.load(tasmota.read_sensors())
 return sensors['ESP32']['Temperature']
end

def report()
 callweb(wurl,gettemp())
end

tasmota.add_cron("*/30 * * * * *", report, "every_30_s")
