#!/usr/bin/env ruby
# kindle_collections.rb -- Automatically manage kindle collections
# @Author:      Tom Link (micathom AT gmail com)
# @License:     GPL (see http://www.gnu.org/licenses/gpl.txt)
# @Created:     2011-11-11.
# @Last Change: 2011-12-01.
# @Revision:    152

# require ''

require 'optparse'
require 'fileutils'
require 'rbconfig'
require 'logger'
require 'digest/sha1'
if RUBY_VERSION =~ /^1\.8/
    require 'rubygems'
    require 'json/pure'
else
    require 'json'
end

class KindleCollections
    APPNAME = 'kindle_collections.rb'
    VERSION = '0.0'
    HELP = {}
    CONFIGS = []
    if ENV['WINDIR']
        CONFIGS << File.join(File.dirname(ENV['WINDIR'].gsub(/\\/, '/')) ,'kindle_collections.yml')
    else
        CONFIGS << '/etc/kindle_collections.yml'
    end
    if ENV['HOME']
        CONFIGS << File.join(ENV['HOME'].gsub(/\\/, '/'), '.kindle_collections.yml')
        if ENV['HOSTNAME']
            CONFIGS << File.join(ENV['HOME'].gsub(/\\/, '/'), ".kindle_collections_#{ENV['HOSTNAME']}.yml")
        end
    elsif ENV['USERPROFILE']
        CONFIGS << File.join(ENV['USERPROFILE'].gsub(/\\/, '/'), 'kindle_collections.yml')
    end
    CONFIGS.delete_if {|f| !File.exist?(f)}

    class AppLog
        def initialize(output=$stdout)
            @output = output
            $logger = Logger.new(output)
            $logger.progname = defined?(APPNAME) ? APPNAME : File.basename($0, '.*')
            $logger.datetime_format = "%H:%M:%S"
            AppLog.set_level
        end
    
        def self.set_level
            if $DEBUG
                $logger.level = Logger::DEBUG
            elsif $VERBOSE
                $logger.level = Logger::INFO
            else
                $logger.level = Logger::WARN
            end
        end
    end


    class << self
    
        def with_args(args)
    
            AppLog.new
    
            config = Hash.new
            config['dir'] = Dir.pwd
            config['subdirs'] = ['documents']
            config['collections'] = {}
            config['json'] = ''
            config['locale'] = 'en-US'
            config['rx'] = /\.(azw|mobi|txt|pdf)$/
            config['kindle_version'] = 2
            config['collection_patterns'] = {}
            CONFIGS.each do |file|
                begin
                    config.merge!(YAML.load_file(file))
                rescue TypeError
                    $logger.error "Error when reading configuration file: #{file}"
                end
            end
            opts = OptionParser.new do |opts|
                opts.banner =  "Usage: #{File.basename($0)} [OPTIONS]"
                opts.separator ' '
                opts.separator 'kindle_collections.rb is a free software with ABSOLUTELY NO WARRANTY under'
                opts.separator 'the terms of the GNU General Public License version 2 or newer.'
                opts.separator ' '

                opts.separator 'General Options:'

                opts.on('-d', '--dir DIR', String, 'Kindle base directory') do |value|
                    config['dir'] = value
                end

                opts.on('-j', '--json FILE', String, 'Re-use an existing collections.json') do |value|
                    config['json'] = value
                end

                opts.on('-k VERSION', '--kindle VERSION', Integer, 'Kindle version (default: 2)') do |value|
                    config['kindle_version'] = value
                end
                
                opts.on('-p', '--pattern REGEXP', String, 'Register only files matching this regular expression') do |value|
                    config['rx'] = Regexp.new(value)
                end

                opts.on('--print-config', 'Print the configuration and exit') do |bool|
                    # puts "Configuration files: #{CONFIGS}"
                    puts YAML.dump(config)
                    exit
                end

                opts.on('--print-collections [COLLECTION REGEXP]', 'Print the collections for debugging purposes and exit') do |rx|
                    config['print-collections'] = rx
                end

                opts.on('--print-diff JSON', String, 'Print entries in a JSON file that are not included in a current scan') do |value|
                    config['print-diff'] = value
                end
                
                opts.on('-s', '--subdir DIR', String, 'Add sub-directory') do |value|
                    config['subdir'] << value
                end

                opts.separator ' '
                opts.separator 'Other Options:'
            
                opts.on('--debug', 'Show debug messages') do |v|
                    $DEBUG   = true
                    $VERBOSE = true
                    AppLog.set_level
                end
            
                opts.on('-v', '--verbose', 'Run verbosely') do |v|
                    $VERBOSE = true
                    AppLog.set_level
                end
            
                opts.on_tail('-h', '--help', 'Show this message') do
                    puts opts
                    exit 1
                end
            end
            $logger.debug "command-line arguments: #{args}"
            argv = opts.parse!(args)
            $logger.debug "config: #{config}"
            $logger.debug "argv: #{argv}"
            if argv.count > 0
                $logger.fatal "Unused arguments: #{argv.inspect}"
                exit 5
            end
            if config['kindle_version'] != 2
                $logger.fatal "Only kindle version 2 is supported"
                exit 5
            end

            unless config['json'].nil? or config['json'].empty?
                if File.exists?(config['json'])
                    $logger.info "Read base JSON file: #{config['json']}"
                    serialized = File.read(config['json'])
                    begin
                        config['collections'] = JSON.parse(serialized)
                    rescue JSON::ParserError => e
                        $logger.error "Error when parsing JSON file #{config['json'].inspect}: #{e}"
                    end
                else
                    $logger.error "JSON file does not exist: #{config['json']}"
                end
            end
    
            return KindleCollections.new(config, argv)
        end
    
    end

    # config ... hash
    # args   ... array of strings
    def initialize(config, args)
        @config = config
        @args   = args
        @files  = []
        @collections = {}
        @ids = {}
    end

    def process
        collect_files
        classify_files
        if @config.has_key?('print-diff')
            print_diff
        elsif @config.has_key?('print-collections')
            print_colls
        else
            write_json
        end
    end

    def collect_files
        @files  = []
        file_rx = @config['rx']
        if !file_rx.kind_of?(Regexp)
            file_rx = Regexp.new(file_rx)
        end
        FileUtils.cd(@config['dir']) do
            for subdir in @config['subdirs']
                $logger.debug "Scan subdir: #{subdir}"
                if File.directory?(subdir)
                    pattern = File.join(subdir, '**', '*')
                    $logger.debug "Use pattern: #{pattern}"
                    files = Dir[pattern]
                    files.delete_if {|filename| File.directory?(filename) || filename !~ file_rx}
                    @files += files
                end
            end
        end
        $logger.debug @files.inspect
    end

    def classify_files
        @collections = {}.merge(@config['collections'])
        @files.each do |filename|
            unless File.directory?(filename)
                collection_names = match_filename(filename)
                if collection_names.empty?
                    parts = filename.split(/[\\\/]/)
                    if parts.count > 2
                        collection_names << "#{parts[1]}@#{@config['locale']}"
                    end
                end
                for collection in collection_names
                    @collections[collection] ||= {'items' => []}
                    id = if filename =~ /^.*?-asin_([a-zA-Z0-9_]+)-type_([a-zA-Z0-9_]+)-v_([0-9]+)\.([^[:space:].]+)$/
                             "##{$1}^#{$2}"
                         else
                             "*#{Digest::SHA1.hexdigest("/mnt/us/#{filename}")}"
                         end
                    $logger.debug "#{filename} :: #{collection} << #{id}"
                    @collections[collection]['items'] << id
                    @ids[id] = filename
                end
            end
        end
        $logger.info "Collections: #{@collections.count}"
    end

    def match_filename(filename)
        collection_names = []
        unclassified = nil
        $logger.debug "Match filename: #{filename}"
        for collection, patterns in @config['collection_patterns']
            $logger.debug "Match patterns (#{collection}): #{patterns.join(", ")}"
            for pattern in patterns
                case pattern
                when :else
                    unclassified = collection
                else
                    if filename =~ Regexp.new(pattern)
                        collection_names << "#{collection}@#{@config['locale']}"
                        break
                    end
                end
            end
        end
        if collection_names.empty? and ! unclassified.nil?
            collection_names << unclassified
        end
        $logger.debug "Add #{filename.inspect} to: #{collection_names.join(", ")}" unless collection_names.empty?
        return collection_names
    end

    def write_json
        serialized = @collections.to_json
        $logger.debug "JSON: #{serialized}"
        collections_json = File.join(@config['dir'], 'system', 'collections.json')
        if File.exists?(collections_json)
            collections_bak = File.join(@config['dir'], 'system', "collections_bak_#{Time.now.strftime("%Y-%m-%d")}.json")
            $logger.info "Backup collections.json to #{collections_bak}"
            File.rename(collections_json, collections_bak)
        end
        $logger.warn "Write #{collections_json}"
        File.open(collections_json, "w") {|f| f.print serialized}
        $logger.warn "You have to hard reset the kindle for the changes to take effect!"
    end

    def print_colls
        rx = @config['print-collections'].nil? ? nil : Regexp.new(@config['print-collections'])
        for collection, vals in @collections
            if rx.nil? or collection =~ rx
                hd = "Collection: #{collection}"
                puts hd
                puts ("=" * hd.length)
                for id in vals['items']
                    filename = @ids[id] || "[PRE-CONFIGURED ENTRY: #{id}]"
                    puts "    - #{filename}"
                end
                puts
            end
        end
    end

    def print_diff
        if File.exists?(@config['print-diff'])
            serialized = File.read(@config['print-diff'])
            other = JSON.parse(serialized)
            diff = {}
            for collection, vals in other
                if @collections.has_key?(collection)
                    collected_items = @collections[collection]['items']
                    for item in vals['items']
                        unless collected_items.include?(item)
                            diff[collection] ||= {'items' => []}
                            diff[collection]['items'] << item
                        end
                    end
                else
                    diff[collection] = vals
                end
            end
            puts diff.to_json
        else
            $logger.error "JSON file does not exist: #{@config['print-diff']}"
        end
    end
end


if __FILE__ == $0
    KindleCollections.with_args(ARGV).process
end

