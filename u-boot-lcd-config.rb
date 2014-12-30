#!/usr/bin/env ruby
#
# Copyright © 2014 Siarhei Siamashka <siarhei.siamashka@gmail.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require 'find'

def parse_fex_section(filename, section)
  results = {}
  current_section = ""
  File.open(filename).each_line { |l|
    current_section = $1 if l =~ /^\[(.*?)\]/
    next if current_section != section
    results[$1] = $2.strip if l =~ /^(\S+)\s*\=\s*(.*)/
    results[$1] = $2.to_i if l =~ /^(\S+)\s*\=\s*(\d+)\s*$/
  }
  results.delete_if { |_, v| v == "" || v == "\"\"" }
  return results
end

def get_config_video_lcd_mode(lcd0_para, soc_name)
  vt_div = case soc_name
           when "a10", "a10s", "a13", "a20" then 2
           when "a23", "a31", "a31s" then 1
           else abort("error: unknown soc name #{soc_name}")
           end

  x        = lcd0_para["lcd_x"]
  y        = lcd0_para["lcd_y"]
  depth    = 18
  pclk_khz = lcd0_para["lcd_dclk_freq"] * 1000
  hs       = [1, (lcd0_para["lcd_hv_hspw"] || lcd0_para["lcd_hspw"])].max
  vs       = [1, (lcd0_para["lcd_hv_vspw"] || lcd0_para["lcd_vspw"])].max
  le       = lcd0_para["lcd_hbp"] - hs
  ri       = lcd0_para["lcd_ht"] - x - lcd0_para["lcd_hbp"]
  up       = lcd0_para["lcd_vbp"] - vs
  lo       = lcd0_para["lcd_vt"] / vt_div - y - lcd0_para["lcd_vbp"]

  sprintf("CONFIG_VIDEO_LCD_MODE=\"" +
          "x:#{x},y:#{y},depth:#{depth},pclk_khz:#{pclk_khz}," +
          "le:#{le},ri:#{ri},up:#{up},lo:#{lo},hs:#{hs},vs:#{vs}," +
          "sync:3,vmode:0\"")
end

def decode_gpio(gpio)
    return unless gpio =~ /port\:(P[A-Z])(\d+)\</
    return $1 + $2.to_i.to_s
end

def decode_lcd_if(lcd_if)
   return case lcd_if
          when 0 then "LCD_IF_HV"
          when 1 then "LCD_IF_CPU"
          when 3 then "LCD_IF_LVDS"
          when 4 then "LCD_IF_DSI"
          when 5 then "LCD_IF_EDP"
          when 6 then "LCD_IF_EXT_DSI"
          end
end

# Search all fex files

Find.find("sys_config") { |filename|
  next unless filename =~ /\/(?<soc_name>[^\/]+)\/(?<board_name>[^\/]+)\.fex$/
  soc_name = $1
  board_name = $2

  lcd0_para = parse_fex_section(filename, "lcd0_para")
  next unless lcd0_para && lcd0_para["lcd_used"] == 1


  if lcd0_para["lcd_if"] != 0
#    printf("# warning: unsupported 'lcd_if' : %s (%d)\n\n",
#           decode_lcd_if(lcd0_para["lcd_if"]), lcd0_para["lcd_if"])
    next
  end

  if lcd0_para["lcd_frm"] != 1
#    printf("# warning: unsupported 'lcd_frm' : %s\n\n",
#           lcd0_para["lcd_frm"].to_s)
    next
  end

  printf("=== %s (%s) ===\n", board_name, soc_name)

  config_video_lcd_mode = get_config_video_lcd_mode(lcd0_para, soc_name)

  if config_video_lcd_mode
    printf("%s\n", config_video_lcd_mode)

    ######################## lcd_power ##############################

    if lcd0_para["lcd_power_used"] != 0 && lcd0_para["lcd_power"]
      pin_name = decode_gpio(lcd0_para["lcd_power"])
      if pin_name
        printf("CONFIG_VIDEO_LCD_POWER=\"%s\"\n", pin_name)
      else
        printf("# warning: could not decode 'lcd_power' (%s)\n",
               lcd0_para["lcd_power"])
      end
    end

    ######################## lcd_bl_en ##############################

    if lcd0_para["lcd_bl_en_used"] != 0 && lcd0_para["lcd_bl_en"]
      pin_name = decode_gpio(lcd0_para["lcd_bl_en"])
      if pin_name
        printf("CONFIG_VIDEO_LCD_BL_EN=\"%s\"\n", pin_name)
      else
        printf("# warning: could not decode 'lcd_bl_en' (%s)\n",
               lcd0_para["lcd_bl_en"])
      end
    end

    ######################## lcd_pwm ##############################

    if lcd0_para["lcd_pwm_used"] && lcd0_para["lcd_pwm_not_used"] &&
       lcd0_para["lcd_pwm_used"] == lcd0_para["lcd_pwm_not_used"]
    then
      printf("# warning: contradicting 'lcd_pwm_used' and 'lcd_pwm_not_used'\n")
    end

    if lcd0_para["lcd_pwm_used"] != 0 && lcd0_para["lcd_pwm_not_used"] != 1 &&
                                         lcd0_para["lcd_pwm"]
      pin_name = decode_gpio(lcd0_para["lcd_pwm"])
      if pin_name
        printf("CONFIG_VIDEO_LCD_BL_PWM=\"%s\"\n", pin_name)
      else
        printf("# warning: could not decode 'lcd_pwm' (%s)\n",
               lcd0_para["lcd_pwm"])
      end

    elsif lcd0_para["lcd_pwm_used"] == 1 && lcd0_para["lcd_pwm_not_used"] != 1 &&
                                            !lcd0_para["lcd_pwm"]
      pwm_para_section_name = sprintf("pwm%d_para", lcd0_para["lcd_pwm_ch"])
      pwm_para = parse_fex_section(filename, pwm_para_section_name)
      if pwm_para
        printf("# warning: 'lcd_pwm' gpio extracted from '%s' section\n",
               pwm_para_section_name)
        pin_name = decode_gpio(pwm_para["pwm_positive"])
        if pin_name
          printf("CONFIG_VIDEO_LCD_BL_PWM=\"%s\"\n", pin_name)
        else
          printf("# warning: could not decode 'pwm_positive' (%s)\n",
                 pwm_para["pwm_positive"])
        end
      else
        printf("warning: no '%s' section found\n", pwm_para_section_name)
      end
    end

    ###############################################################

    ["lcd_gpio_0", "lcd_gpio_1", "lcd_gpio_2", "lcd_gpio_3",
     "lcd_gpio_scl", "lcd_gpio_sda"].each {|gpio|
      if lcd0_para[gpio]
        printf("# warning: '%s' = '%s'\n", gpio, lcd0_para[gpio])
      end
    }

    printf("\n")
  end
}
