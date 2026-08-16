import string
import mqtt

class Vibration
  var wire
  var ax
  var ay
  var az
  var avg_x
  var avg_y
  var avg_z
  var initialized
  var vibration2
  var detected
  var threshold
  var sample_count
  var sum_vibration2
  var peak_vibration2
  var average2
  var reported
  var last_detect_time
  var hold_time_ms
  var dlpf_cfg
  var mqtt_ready
  var unitname
  var stattopic
  var teletopic
  var macid
  var discovery_prefix
  var last_publish_value
  var last_publish_peak
  var calibrated
  var calibrating
  var calib_start_ms
  var calib_settle_ms
  var calib_time_ms
  var calib_list
  var calib_factor
  var min_threshold
  var consecutive_yes
  var confirm_samples
  var strong_mult

  def init()
    self.wire = tasmota.wire_scan(0x68)

    self.ax = 0
    self.ay = 0
    self.az = 0

    self.avg_x = 0
    self.avg_y = 0
    self.avg_z = 0

    self.initialized = false
    self.vibration2 = 0
    self.detected = false
    self.reported = false

    # Sensitivity: single-axis deviation of sqrt(threshold) LSB (~164 LSB/g at 2g range)
    # Tuning: watch the resting Peak2 in the console, set threshold ~1.5-2x above it.
    #   - 8000 ~ 0.017 g, 6000 ~ 0.015 g, 4000 ~ 0.012 g. Lower = more sensitive (risk of noise triggers).
    self.threshold = 6000
    self.consecutive_yes = 0
    self.confirm_samples = 2
    self.strong_mult = 1.5

    self.sample_count = 0
    self.sum_vibration2 = 0
    self.peak_vibration2 = 0
    self.average2 = 0

    self.last_detect_time = 0
    self.hold_time_ms = 2000
    self.dlpf_cfg = 4

    self.mqtt_ready = false
    self.unitname = ""
    self.stattopic = ""
    self.teletopic = ""
    self.macid = ""
    self.discovery_prefix = "homeassistant"
    self.last_publish_value = nil
    self.last_publish_peak = nil

    self.calibrated = false
    self.calibrating = false
    self.calib_start_ms = 0
    self.calib_settle_ms = 1000
    self.calib_time_ms = 3000
    self.calib_list = []
    self.calib_factor = 2.0
    self.min_threshold = 3000

    if !self.wire
      print("MPU6050 not found")
    else
      print("MPU6050 found")

      self.wire.write(0x68, 0x6B, 0x00, 1)
      tasmota.delay(10)

      self.wire.write(0x68, 0x6B, 0x01, 1)
      self.wire.write(0x68, 0x1C, 0x00, 1)
      self.wire.write(0x68, 0x1B, 0x00, 1)

      # DLPF_CFG = 4 (21 Hz accel bandwidth): much lower noise, good for detecting weak vibrations
      # DLPF_CFG = 1 (184 Hz): higher bandwidth but ~3x more resting noise (easy false triggers)
      self.wire.write(0x68, 0x1A, self.dlpf_cfg, 1)

      # 100 Hz
      self.wire.write(0x68, 0x19, 0x09, 1)

      tasmota.delay(20)

      print("MPU6050 configured")
      print("DLPF register set to ", self.dlpf_cfg)
      print("Threshold = ", self.threshold)
      print("Hold time = ", self.hold_time_ms, " ms")
    end

    if mqtt.connected
      self.mqtt_setup()
    else
      tasmota.add_rule("MQTT#Connected=1", / -> self.mqtt_setup(), "vibration_mqtt")
    end
  end

  def getmac(cter)
    var mac = ""
    var ni = tasmota.eth()
    if ni != nil
      if ni.has('mac')
        mac = ni['mac']
      end
    end
    if mac == ""
      ni = tasmota.wifi()
      if ni != nil
        if ni.has('mac')
          mac = ni['mac']
        end
      end
    end
    mac = string.replace(mac, ":", "")
    if cter > 0
      var slen = size(mac)
      if slen > cter
        mac = mac[(slen-cter) .. (slen-1)]
      end
    end
    return mac
  end

  def mqtt_setup()
    var topic_result = tasmota.cmd('Topic')
    if topic_result == nil
      print("MQTT setup: Topic command returned nil")
      return
    end
    if !topic_result.has('Topic')
      print("MQTT setup: Topic not available")
      return
    end
    var full_result = tasmota.cmd('FullTopic')
    if full_result == nil
      print("MQTT setup: FullTopic command returned nil")
      return
    end
    if !full_result.has('FullTopic')
      print("MQTT setup: FullTopic not available")
      return
    end
    var prefix_result = tasmota.cmd('Prefix')
    if prefix_result == nil
      print("MQTT setup: Prefix command returned nil")
      return
    end
    self.macid = self.getmac(6)
    self.unitname = string.replace(topic_result['Topic'], "%06X", self.macid)
    var fulltopic = full_result['FullTopic']
    var prefix = prefix_result
    self.teletopic = string.replace(string.replace(fulltopic, '%topic%', self.unitname), '%prefix%', prefix['Prefix3'])
    self.stattopic = string.replace(string.replace(fulltopic, '%topic%', self.unitname), '%prefix%', prefix['Prefix2'])
    self.mqtt_ready = true
    print("Vibration MQTT ready: ", self.stattopic)
    self.publish_discovery()
    self.publish_state()
    self.publish_value(true)
  end

  def publish_discovery()
    if !self.mqtt_ready
      return
    end
    try
      var dtopic = self.discovery_prefix + "/binary_sensor/" + self.macid + "_vibration/config"
      var dpl = '{"name": "' + self.unitname + ' Vibration","stat_t": "' + self.stattopic + 'VIBRATION","avty_t": "' + self.teletopic + 'LWT","pl_avail": "Online","pl_not_avail": "Offline","pl_on": "ON","pl_off": "OFF","uniq_id": "' + self.macid + '_vibration","dev": {"ids": ["' + self.macid + '"]},"dev_cla": "vibration"}'
      mqtt.publish(dtopic, dpl, true)

      dtopic = self.discovery_prefix + "/sensor/" + self.macid + "_vibration_value/config"
      dpl = '{"name": "' + self.unitname + ' Vibration level","stat_t": "' + self.stattopic + 'VIBRATION_VALUE","avty_t": "' + self.teletopic + 'LWT","pl_avail": "Online","pl_not_avail": "Offline","uniq_id": "' + self.macid + '_vibration_value","icon": "mdi:vibrate","dev": {"ids": ["' + self.macid + '"]}}'
      mqtt.publish(dtopic, dpl, true)

      dtopic = self.discovery_prefix + "/sensor/" + self.macid + "_vibration_peak/config"
      dpl = '{"name": "' + self.unitname + ' Vibration peak","stat_t": "' + self.stattopic + 'VIBRATION_PEAK","avty_t": "' + self.teletopic + 'LWT","pl_avail": "Online","pl_not_avail": "Offline","uniq_id": "' + self.macid + '_vibration_peak","icon": "mdi:chart-line-variant","dev": {"ids": ["' + self.macid + '"]}}'
      mqtt.publish(dtopic, dpl, true)
    except .. as e, v
      print("Vibration discovery error: ", str(e), str(v))
    end
  end

  def publish_state()
    if !self.mqtt_ready
      return
    end
    var s = "OFF"
    if self.reported
      s = "ON"
    end
    mqtt.publish(self.stattopic + "VIBRATION", s)
    self.publish_value()
  end

  def publish_value(force)
    if !self.mqtt_ready
      return
    end
    if force || self.average2 != self.last_publish_value || self.peak_vibration2 != self.last_publish_peak
      self.last_publish_value = self.average2
      self.last_publish_peak = self.peak_vibration2
      mqtt.publish(self.stattopic + "VIBRATION_VALUE", string.format('%.1f', self.average2))
      mqtt.publish(self.stattopic + "VIBRATION_PEAK", string.format('%.1f', self.peak_vibration2))
    end
  end

  def read_accel()
    if !self.wire
      return false
    end

    var b = self.wire.read_bytes(0x68, 0x3B, 6)

    if b == nil
      return false
    end

    var x = b.get(0, -2)
    var y = b.get(2, -2)
    var z = b.get(4, -2)

    if x >= 32768
      x = x - 65536
    end

    if y >= 32768
      y = y - 65536
    end

    if z >= 32768
      z = z - 65536
    end

    self.ax = x
    self.ay = y
    self.az = z

    return true
  end

  def process()
    if !self.read_accel()
      return
    end

    if !self.initialized
      self.avg_x = self.ax
      self.avg_y = self.ay
      self.avg_z = self.az
      self.initialized = true
      return
    end

    var alpha = 0.01

    self.avg_x = self.avg_x + alpha * (self.ax - self.avg_x)
    self.avg_y = self.avg_y + alpha * (self.ay - self.avg_y)
    self.avg_z = self.avg_z + alpha * (self.az - self.avg_z)

    var dx = self.ax - self.avg_x
    var dy = self.ay - self.avg_y
    var dz = self.az - self.avg_z

    self.vibration2 = dx * dx + dy * dy + dz * dz

    if self.vibration2 >= self.threshold
      self.detected = true
    else
      self.detected = false
    end

    self.sum_vibration2 = self.sum_vibration2 + self.vibration2
    self.sample_count = self.sample_count + 1

    if self.vibration2 > self.peak_vibration2
      self.peak_vibration2 = self.vibration2
    end
  end

  def _isort(arr)
    var n = size(arr)
    var i = 1
    while i < n
      var key = arr[i]
      var j = i - 1
      while j >= 0 && arr[j] > key
        arr[j + 1] = arr[j]
        j = j - 1
      end
      arr[j + 1] = key
      i = i + 1
    end
  end

  def calibrate()
    if self.calibrated
      return
    end
    if !self.initialized
      return
    end
    if !self.calibrating
      self.calibrating = true
      self.calib_start_ms = tasmota.millis()
      self.calib_list = []
      print("Calibrating resting noise for ", self.calib_settle_ms + self.calib_time_ms, " ms ...")
      return
    end
    var elapsed = tasmota.millis() - self.calib_start_ms
    if elapsed < self.calib_settle_ms
      return
    end
    if elapsed < self.calib_settle_ms + self.calib_time_ms
      self.calib_list.push(self.vibration2)
      return
    end
    self._isort(self.calib_list)
    var n = size(self.calib_list)
    if n >= 5
      var p95 = self.calib_list[int(n * 0.95)]
      var median = self.calib_list[int(n / 2)]
      var t = p95 * self.calib_factor
      if t < self.min_threshold
        t = self.min_threshold
      end
      self.threshold = t
      print("Calibration done: samples=", n, " median=", median, " p95=", p95, " threshold=", self.threshold)
    else
      print("Calibration failed (too few samples), keeping threshold=", self.threshold)
    end
    self.calibrating = false
    self.calibrated = true
  end

  def recalibrate()
    self.calibrating = false
    self.calibrated = false
    self.calib_list = []
    print("Restarting calibration ...")
  end

  def every_50ms()
    self.process()
    self.calibrate()

    if self.calibrating
      return
    end

    # Confirmed detection with two thresholds:
    # - need `confirm_samples` consecutive samples above the threshold (a short
    #   burst at rest rarely lasts two contiguous 50ms samples),
    # - a single strong sample at >= strong_mult x threshold trips immediately
    #   (catches hard, very short taps even when the first sample is a spike).
    if self.detected
      self.consecutive_yes = self.consecutive_yes + 1
    else
      self.consecutive_yes = 0
    end

    var trig = false
    if self.detected && (self.consecutive_yes >= self.confirm_samples || self.vibration2 >= self.strong_mult * self.threshold)
      trig = true
    end

    if trig
      self.last_detect_time = tasmota.millis()
      if !self.reported
        self.reported = true
        self.publish_state()
      end
    else
      if self.reported
        if tasmota.time_reached(self.last_detect_time + self.hold_time_ms)
          self.reported = false
          self.publish_state()
        end
      end
    end
  end

  def every_second()
    if !self.wire
      return
    end

    if self.sample_count > 0
      self.average2 = self.sum_vibration2 / self.sample_count

      print(
        "Vibration2 = ",
        self.vibration2,
        " Average2 = ",
        self.average2,
        " Peak2 = ",
        self.peak_vibration2,
        " Detected = ",
        self.detected,
        " Samples = ",
        self.sample_count
      )

      self.publish_value()
    end

    self.sample_count = 0
    self.sum_vibration2 = 0
    self.peak_vibration2 = 0
  end
end

var vibration = Vibration()

tasmota.add_driver(vibration)

print("MPU6050 vibration detector started")