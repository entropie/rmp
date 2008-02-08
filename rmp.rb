#!/usr/bin/env ruby
# -*- mode:ruby -*-

#
#
# Author:  Michael 'entropie' Trommer <mictro@gmail.com>
#

#
# = Dead simple extensible np script
#
#  puts (if ARGV.size > 0
#    NP.run(:use => [:ssh, { :user => :mit, :server => :tie} ] )
#  else
#    NP.run
#  end)
#
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
  
  def self.run(opts = { })
    selecter = Selecter
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
    selecter.run(runner)
  end
  
  class Selecter
    include NP
    attr_writer :output
    attr_accessor :result

    def self.run(runner)
      runner.select{ |r|
        r.match
      }
    end
    def self.inherited(o)
      NP.runner << o.new
    end

    def match
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
      super.gsub(/\):( )/, "@#{server})")
    end
  end
  
  class MPD < Selecter
    def output
      @output ||= sh 'mpc play'
    end

    def match
      lines = output.split("\n")
      lines.size == 3 and lines[0] =~ (/-/) or return false
      @result = lines[0]
      super
    end
  end
  
  class MPlayer < Selecter
    def output
      @output ||= sh 'ps fax | grep mplayer'
    end

    def match
      @result = output.split("\n").inject([]) do |m, l|
        m << l.scan(/mplayer (.*$)$/m) unless l.to_s.strip.empty?
      end.uniq.to_s
      return false if @result.empty?
      super
    end
  end

end

puts (if ARGV.size > 0
  NP.run(:use => [:ssh, { :user => :mit, :server => :tie} ] )
else
  NP.run
end)


