#!/usr/bin/env ruby
# -*- mode:ruby -*-

#
#
# Author:  Michael 'entropie' Trommer <mictro@gmail.com>
#

require 'delegate'
require 'open-uri'
require 'nokogiri'

module NP

  def runner
    @sel ||= []
  end
  module_function :runner

  def sh(arg)
    `#{arg}`.to_s
  end

  module_function :sh

  def skip=(arr)
    @skip = arr
  end

  module_function 'skip='

  def skip
    @skip ||= []
  end

  module_function :skip

  # delegates selecter
  class Filter < SimpleDelegator

    def initialize(o)
      @sel = o
    end

    def apply!
      @sel
    end

    def __getobj__
      @sel
    end

    def self.filter_for(o)
      Filter.constants.map{ |c| Filter.const_get(c) }.map do |const|
        const.filter!(o) rescue nil
      end.compact
    end

    # class LoungeRadio < Filter
    #   URL = "http://www.lounge-radio.com/code/pushed_files/now.html"
    #   def self.filter!(o)
    #     self.new(o).apply! if o.result =~ %r(LOUNGE-RADIO.COM)
    #   end
    #   def apply!
    #     res = Nokogiri::HTML(URI.open(URL))
    #     fs = res.search('div#container').map {|e| e.inner_text }.to_s.split(/\r\n/m).map{|s| s.strip}.reject {|s| s.empty?}[1..-2]
    #     fs.reject!{ |f| f =~ /<img/ } # remove playlist img
    #     fs = Hash[*fs]
    #     result.replace "lounge radio: #{fs['Artist:']} - #{fs['Track:']}  (#{fs['Album:']})"
    #   end
    # end

  end

  def self.run(opts = { })
    selecter = Selector
    selecter.run(runner, skip)
  end

  class Selector
    include NP
    attr_writer :output
    attr_accessor :result

    def self.run(runner, skip = [])
      runner.select{ |r|
        not skip.include?(r.class) and r.match
      }
    end
    def self.inherited(o)
      NP.runner << o.new
    end

    def match
      Filter.filter_for(self)
      true
    end

    def name
      "#{self.class.name}".split('::').last.downcase
    end

    def to_s
      "NP(#{name}): #{result}"
    end
  end

  class MPD < Selector
    def output
      @output ||= sh 'mpc status 2>&1'
      @output = "" if @output =~ /connection refused/
      @output ||= ''
    end

    def match
      lines = output.split("\n")
      lines.size == 3 and
        (lines[0] =~ (/-/) or
         lines[0] =~ /\.mp3$/i or
         lines[0] =~ /\.ogg$/i) or
        return false
      @result = lines[0]
      super
    end
  end if ENV["MPD_HOST"]


  class Playerctl < Selector

    class PCTLEntry
      include NP

      def self.entry_handler(t = nil)
        @entry_handler ||= Playerctl.constants.select{ |c| "Entry" == c.to_s[0..4]}
        if t
          ret = @entry_handler.select{ |eh| eh.to_s.downcase =~ /#{t}/ }.shift
          return Playerctl.const_get(ret)
        end

        @entry_handler
      end

      def self.parse_pctl_output(output )
        return nil if not output or output.empty?
        clzs = Playerctl.constants.select{ |c| "Entry" == c.to_s[0..4]}
        output.map do |line|
          clz = entry_handler(line.split(".").first)
          clz = clz.new(line)
          clz
        end
      end

      def initialize(str)
        @string = str
      end

      def handler
        @string.split(".").first
      end

      def result
        return "" unless `which playerctl`
        artist = sh "playerctl -p #{handler} metadata --format '{{artist}}'"
        title  = sh "playerctl -p #{handler} metadata --format '{{title}}'"
        if artist.strip.empty?
          @result = "%s" % [title]
        else
          @result = "%s - %s" % [artist.strip, title.strip]
        end
      end

      def to_s
        "NP(#{handler}): #{result}"
      end
    end

    class EntrySpotify < PCTLEntry
    end

    class EntryBrave < PCTLEntry
    end


    def playerctl
      @playerctl ||= `playerctl -l`.split
    rescue
      nil
    end
    
    def output
      @output = playerctl
      return "" if not @output or @output.empty?

      result_arr = PCTLEntry.parse_pctl_output(@output)
      @output = result_arr.join
    end

    def match
      @result ||= output
      super
    end

    def to_s
      @result
    end
  end
  

  class Pulseaudio < Selector

    def pactl_awk
      cmd = <<~SH
    pactl list sink-inputs | awk '
      /application.name =/ {
        gsub(/"/, "", $3); app=$3
        for (i=4; i<=NF; i++) { gsub(/"/, "", $i); app = app " " $i }
        print app
      }
      /media.name =/ {
        gsub(/"/, "", $3); title=$3
        for (i=4; i<=NF; i++) { gsub(/"/, "", $i); title = title " " $i }
        print title
      }
    '
  SH
    end

    def to_s
      hash = @result.each_slice(2).to_h
      hash.select!{ |h,k| h != "spotify" }
      hash.select!{ |h,k| h != "Brave" }

      hash.inject("") do |res, h|
        h.unshift h.shift.to_s.downcase
        res << "NP(%s): %s\n" % [*h]
      end
    end

    def self.running?
      @pulseaudio ||= `which pactl > /dev/null 2>&1`
    end

    def output
      return "" unless Pulseaudio.running?
      @result = `#{pactl_awk}`.split("\n")
      if not @result or @result.empty?
        return ""
      end
      @result
    end

    def match
      return false if output.size == 0
      @result = output
      super
    end

  end
end

NP.skip = []

if __FILE__ == $0
  puts NP.run
end

__END__
# License: GPL
#
# rmp - a np script
# Copyright (C) Michael 'mictro' Trommer <mictro@gmail.com>
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
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
