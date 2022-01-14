require "digest/sha1"
require "fileutils"
require "open-uri"
require "uri"

module Sss
  module Installer
    class SnapPackage
        def initialize(name, options)
          @name = name
          @install_flags = options.select{ |option| option == :classic }.map{ |option| "--#{option.to_s}" }
        end
      
        def to_s
          @name
        end
      
        def installed?
          package_rows = %x(snap list)
      
          package_rows.split("\n").find{ |package_row| package_row.split(" ")[0] == @name }
        end
      
        def install
          IO.popen("snap install #{@name} #{@install_flags * " "}") do |io|
            while (line = io.gets) do
              puts(line)
            end
          end
        end
      end
      
      class AptPackage
        def initialize(source)
          @source = source
          @name = nil
        end
      
        def to_s
          @source
        end
      
        def installed?
          %x(dpkg -l #{name})
          $?.exitstatus == 0
        end
      
        def install
          command = if @source =~ URI::regexp
            "sudo dpkg -i #{deb_file}"
          else
            "sudo apt-get install --yes #{@name}"
          end

          IO.popen(command) do |io|
            while (line = io.gets) do
              puts(line)
            end
          end
        end

        private

        def name
          @name ||= if @source =~ URI::regexp
            IO.popen("dpkg --info #{deb_file}") do |io|
              while (line = io.gets) do
                if line.strip.start_with?("Package: ")
                  return line.strip.partition(": ").last
                end
              end
            end
          else
            @source
          end
        end

        def deb_file
          filename = File.join(PACKAGES_DIR, Digest::SHA1.hexdigest(@source))

          unless File.exists?(filename)
            URI.open(@source) do |source_file|              
              File.open(filename, "w") do |destination_file|
                destination_file.write(source_file.read)
              end
            end
          end

          filename
        end
      end
      
      class Command
        def initialize(cmd)
          @cmd = cmd
        end
      
        def to_s
          @cmd
        end
      
        def installed?
          false
        end
      
        def run
          @cmd.split("\n").each do |line|
            IO.popen(line) do |io|
              while (line = io.gets) do
                puts(line)
              end
            end
          end
        end
      end
      
      class NewGroup
        def initialize(name, options)
          @name = name
          @install_flags = options.select{ |option| option == :system }.map{ |option| "--#{option.to_s}" }
        end
      
        def to_s
          @name
        end
      
        def installed?
          File.open("/etc/group") do |file|
            file.each_line do |line|
              return true if line.start_with?(@name)
            end
          end
      
          false
        end
      
        def install
          IO.popen("sudo addgroup --system docker") do |io|
            while (line = io.gets) do
              puts(line)
            end
          end
        end
      end
      
      class NewGroupMember
        def initialize(user, group)
          @user = user
          @group = group
        end
      
        def to_s
          "#{@user} to #{@group}"
        end
      
        def installed?
          %x(groups #{@user}).partition(" : ").last.split(" ").include?(@group)
        end
      
        def install
          IO.popen("sudo adduser #{@user} #{@group}") do |io|
            while (line = io.gets) do
              puts(line)
            end
          end
        end
      end
      
      class Script
        def initialize(source)
          @source = source
          @script = File.join(SCRIPTS_DIR, Digest::SHA1.hexdigest(source))
        end
      
        def to_s
          @source
        end
      
        def installed?
          File.exists?(@script)
        end
      
        def install
          URI.open(@source) do |source_file|
            File.open(@script, "w") do |script_file|
              script_file.write(source_file.read)
            end
          end
      
          IO.popen("bash #{@script}") do |io|
            while (line = io.gets) do
              puts(line)
            end
          end
      
        end
      end
      
      class Directory
        def initialize(directory)
          @directory = directory
        end
      
        def to_s
          @directory
        end
      
        def installed?
          File.directory?(@directory)
        end
      
        def install
          FileUtils.mkdir_p(@directory)
        end
      end

      class GitConf
        def initialize(key, value)
          @key = key
          @value = value
        end

        def to_s
          @key
        end

        def installed?
          %x(git config --get #{@key}).strip == @value
        end

        def install
          IO.popen("git config --global #{@key} #{@value}") do |io|
            while (line = io.gets) do
              puts(line)
            end
          end
        end
      end

      class BashRC
        def initialize(source)
          @source = source
          @hash = Digest::SHA1.hexdigest(source)
        end

        def to_s
          "Appending some code to .bashrc"
        end

        def installed?
          File.open(File.join(Dir.home, ".bashrc"), "r") do |file|
            file.readlines.find{ |line| line.strip == "# WS_START #{@hash}" }
          end
        end

        def install
          File.open(File.join(Dir.home, ".bashrc"), "a") do |file|
            file << <<~CODE

              # WS_START #{@hash}

              #{code.strip}

              # WS_END #{@hash}
            CODE
          end
        end

        private

        def code
          if @source =~ URI::regexp
            URI.open(@source){ |source_file| source_file.read }
          else
            @source
          end
        end
      end

      class Bin
        def initialize(source, command = nil)
          @source = source
          @source_filename = source.split("/").last
          @source_file_basename = @source_filename.partition(".").first
          @command = command || @source_file_basename
          @temp_destination = File.join(BIN_DIR, @source_filename)
          @destination = File.join("/usr/local/bin/", @command)
        end

        def to_s
          @source
        end

        def installed?
          %x(which #{@command})
          $?.exitstatus == 0
        end

        def install
          URI.open(@source) do |source_file|
            File.open(@temp_destination, "wb") do |script_file|
              script_file.write(source_file.read)
              script_file.chmod(0755)
            end
          end

          if @source_filename.end_with?(".tar.gz")
            unarchived_temp_destination = @temp_destination[0, @temp_destination.length - ".tar.gz".length]
            %x(mkdir #{unarchived_temp_destination})
            %x(tar xvf #{@temp_destination} -C #{unarchived_temp_destination})

            # Attempt to find command file in unarchived folder
            command_file = Dir[File.join(unarchived_temp_destination, "**", "*")].find do |file|
              file.split("/").last == @command
            end

            %x(sudo cp #{command_file} #{@destination})
          elsif @source_filename.end_with?(".gz")
            unarchived_temp_destination = @temp_destination[0, @temp_destination.length - ".gz".length]

            %x(zcat #{@temp_destination} > #{unarchived_temp_destination})
            %x(chmod +x #{unarchived_temp_destination})
            %x(sudo cp #{unarchived_temp_destination} #{@destination})
          else
            %x(sudo cp #{@temp_destination} #{@destination})
          end
        end
      end

      class Gsettings
        def initialize(schema, key, value)
          @schema = schema
          @key = key
          @value = value
        end

        def to_s
          "#{@schema} #{@key} to #{@value}"
        end

        def installed?
          %x(gsettings get #{@schema} #{@key}).strip == @value 
        end

        def install
          %x(gsettings set #{@schema} #{@key} '#{@value}')
        end
      end
  end
end