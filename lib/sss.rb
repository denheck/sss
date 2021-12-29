# frozen_string_literal: true

require "paint"
require "thor"

require_relative "sss/installer"
require_relative "sss/version"

module Sss
  SCRIPTS_DIR = File.join(Dir.home, ".ws", "scripts")

  class SetupParser
    attr_reader :installers
  
    def initialize
      @installers = []
    end
  
    def snap(package_name, *opts)
      @installers << Installer::SnapPackage.new(package_name, opts)
    end
  
    def apt(package_name)
      @installers << Installer::AptPackage.new(package_name)
    end
  
    def mkdir(dir)
      @installers << Installer::Directory.new(dir)
    end
  
    def script(source)
      @installers << Installer::Script.new(source)
    end
  
    def new_group(name, *opts)
      @installers << Installer::NewGroup.new(name, opts)
    end
  
    def new_group_member(user, group)
      @installers << Installer::NewGroupMember.new(user, group)
    end

    def git_conf(key, value)
      @installers << Installer::GitConf.new(key, value)
    end

    def bashrc(code)
      @installers << Installer::BashRC.new(code)
    end

    def bin(source, name = nil)
      @installers << Installer::Bin.new(source, name)
    end

    def gsettings(schema, key, value)
      @installers << Installer::Gsettings.new(schema, key, value)
    end
  end

  class Runner < Thor
    def self.exit_on_failure?
      true
    end

    desc "setup MANIFEST", "Setup the workstation from a manifest file"
    def setup(manifest)
      # initialize environment
      FileUtils.mkdir_p(Sss::SCRIPTS_DIR)

      # parse setup file
      contents = File.read(manifest)
      parser = Sss::SetupParser.new
      parser.instance_eval(contents)

      # run installers
      parser.installers.each do |installer|
        if installer.installed?
          puts("#{Paint["(skip)", :green]} #{installer.class.name} '#{installer}' already installed")
        else
          puts("#{Paint["(install)", :green]} Installing #{installer.class.name} '#{installer}'")
          installer.install  
        end
      end
    end
  end

  class Error < StandardError; end
end
