#!/usr/bin/env ruby
# -*- mode:ruby -*-

#
#
# Author:  Michael 'entropie' Trommer <mictro@gmail.com>
#

require 'rubygems'
require 'delegate'
require 'open-uri'
require 'hpricot'


#
# Dead simple extensible np script which supports multible media
# sources and remote access via ssh.
#
#  puts (if ARGV.size > 0
#    NP.run(:use => [:ssh, { :user => :mit, :server => :tie} ] )
#  else
#    NP.run
#  end)
#

HOST = "10.0.187.12"

module NP
  
  def runner
    @sel ||= []
  end
  module_function :runner
  
  def sh(arg)
    `#{arg}`.to_s
  end

  module_function :sh
  

  def self.extension(which)
    self.const_get(which.to_s.upcase.to_sym)
  end

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
        const.filter!(o)
      end.compact
    end

    class LoungeRadio < Filter
      
      URL = "http://www.lounge-radio.com/code/pushed_files/now.html"
      
      def self.filter!(o)
        self.new(o).apply! if o.result =~ %r(mms://stream.green.ch/lounge-radio)
      end

      def apply!
        res = Hpricot.parse(open(URL))
        fs = res.search('div#container').map {|e| e.inner_text }.to_s.split(/\r\n/m).map{|s| s.strip}.reject {|s| s.empty?}[1..-2]
        fs.reject!{ |f| f =~ /<img/ } # remove playlist img
        fs = Hash[*fs]
        result.replace "lounge radio: '#{fs['Artist:']} - #{fs['Track:']}' from '#{fs['Album:']}'"
      end
      
    end

    class DubstemFM < Filter
      
      URL = "http://dubstep.fm/"
      
      def self.filter!(o)
        self.new(o).apply! if o.result =~ %r(DUBSTEP\.FM)
      end

      def apply!
        res = Hpricot.parse(open(URL))
        np = res.search('center').inner_text.gsub(/Now Playing: /, '')
        result.replace "dubstep.fm: '#{np}'"
      end
      
    end

    class SomaFM < Filter

      URLS = {
        :secretagentsoma => %r(Secret Agent: The soundtrack for your stylish, mysterious, dangerous life.),
        :beatblender     => %r(Beat Blender: A late night blend of deep-house & downtempo chill.),
      }
      
      attr_accessor :suburl
      URL = "http://twitter.com/%s"
      
      def self.filter!(o)
        self.new(o).apply! if o.result =~ %r(\[SomaFM\])
      end

      def twitter_site
        self.suburl =
          URLS.select{|key, val|
          result =~ val
        }.flatten.first
      end
      
      def read
        twitter_site
        res = Hpricot.parse(open(URL % suburl))
        self.result = res.search("li.latest-status .entry-content").inner_text[4..-1]
      end
      
      def apply!
        read
        result.replace "soma.fm(#{suburl}): #{result}"
      end
    end

  end

  def self.run(opts = { })
    selecter = Selector
    if use = opts[:use]
      if use.kind_of?(Array) and use.size == 2
        use, args = use
        use = [use].flatten
      else
        args = { }
      end
      use.each { |u, a|
        runner.each{ |r|
          r.extend(extension(u))
          args.each_pair do |iv, i|
            meth = "#{iv}="
            r.send(meth, i) #if r.respond_to?(meth)
          end
        }
      }
    end
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

  module SSH
    USER   = ENV['USER']
    PREFIX = 'ssh '

    attr_accessor :user, :server, :prefix
    def prefix
      @prefix || PREFIX
    end
    
    def user
      @user || USER
    end
    
    def server
      @server || 'localhost'
    end
    
    def sh(arg)
      `#{prefix} #{user}@#{server} #{arg}`
    end

    def to_s
      super.gsub(/\):( )/, "@#{server}) ")
    end
  end
  
  class MPD < Selector
    def output
      if sh('ps ax | grep "mpd"').split("\n").size > 1
        @output ||= sh '/opt/local/bin/mpc status'
      end
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
  end

  class VLC < Selector
    def output
      @output ||= Hpricot.parse(open("http://#{HOST}:8090/np.html")).to_s.strip
    rescue
      ''
    end

    def match
      @result = output.to_s
      return false if @result.empty? or @result.scan(/[A-Za-z]/).empty?
      super
    end
  end

  class Itunes < Selector
    def output
      if sh('ps ax | grep "/MacOS/iTunes -"') =~ /\-psn/
        @output ||= sh 'osascript /Users/mit/bin/np.scpt'
      end
      @output ||= ""
    end

    def match
      lines = output.split("\n")
      not lines.empty? or return false
      @result = lines[0]
      super
    end
  end
  
  class MPlayer < Selector
    def output
      @output ||= sh 'ps ax | grep mplayer'
    end

    def match
      @result = output.split("\n").inject([]) do |m, l|
        unless l.to_s.strip.empty?
          m << l.scan(/mplayer (.*$)$/m).flatten.map{ |l| l.split(" ").last}
        end        
      end.uniq.to_s
      return false if @result.empty?
      super
    end
  end

  class Amarok < Selector
    def output
      @output ||= sh "dcop amarok player title"
    end
    
    def match
      @result = output.to_s
      return false if @result.empty?
      super
    end

  end

  class ShellFM < Selector
    
    NpFile = File.expand_path('~/Tmp/shell-fm.np')

    # i use an alias in my .zshrc like:
    #  alias sfm="shell-fm || rm -f ~/Tmp/shell-fm.np && echo \"removed np file\""
    def output
      @output ||= if File.exists?(NpFile) then sh "cat #{NpFile}".strip else '' end
    end
    def match
      return false if (@result = output.to_s).empty?
      super
    end
  end
end

NP.skip = [NP::Amarok]

puts (if ARGV.size > 0 and ARGV.to_s.strip == "ssh"
        NP.run(:use => [:ssh, { :user => :mit, :server => :tie} ] )
      else
        NP.run
      end) and __FILE__ == $0


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
