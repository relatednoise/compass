module Compass
  module Configuration
    # The Compass configuration data storage class manages configuration data that comes from a variety of
    # different sources and aggregates them together into a consistent API
    # Some of the possible sources of configuration data:
    #   * Compass default project structure for stand alone projects
    #   * App framework specific project structures for rails, etc.
    #   * User supplied explicit configuration
    #   * Configuration data provided via the command line interface
    #
    # There are two kinds of configuration data that doesn't come from the user:
    #
    # 1. Configuration data that is defaulted as if the user had provided it themselves.
    #    This is useful for providing defaults that the user is likely to want to edit
    #    but shouldn't have to provide explicitly when getting started
    # 2. Configuration data that is defaulted behind the scenes because _some_ value is
    #    required.
    class Data

      attr_reader :name
      extend Sass::Callbacks


      include Compass::Configuration::Inheritance
      extend  Compass::Configuration::Paths

      # on_sprite_saved
      # yields the filename
      # usage: on_sprite_saved {|filename| do_something(filename) }
      define_callback :sprite_saved
      chained_method :run_sprite_saved

      # on_sprite_generated
      # yields 'ChunkyPNG::Image'
      # usage: on_sprite_generated {|sprite_data| do_something(sprite_data) }
      define_callback :sprite_generated
      chained_method :run_sprite_generated

      # on_sprite_removed
      # yields the filename
      # usage: on_sprite_removed {|filename| do_something(filename) }
      define_callback :sprite_removed
      chained_method :run_sprite_removed

      # on_stylesheet_saved
      # yields the filename
      # usage: on_stylesheet_saved {|filename| do_something(filename) }
      define_callback :stylesheet_saved
      chained_method :run_stylesheet_saved

      # on_sourcemap_saved
      # yields the filename
      # usage: on_sourcemap_saved {|filename| do_something(filename) }
      define_callback :sourcemap_saved
      chained_method :run_sourcemap_saved

      # on_stylesheet_removed
      # yields the filename
      # usage: on_stylesheet_removed {|filename| do_something(filename) }
      define_callback :stylesheet_removed
      chained_method :run_stylesheet_removed

      # on_sourcemap_removed
      # yields the filename
      # usage: on_sourcemap_removed {|filename| do_something(filename) }
      define_callback :sourcemap_removed
      chained_method :run_sourcemap_removed

      # on_stylesheet_error
      # yields the filename & message
      # usage: on_stylesheet_error {|filename, message| do_something(filename, message) }
      define_callback :stylesheet_error
      chained_method :run_stylesheet_error

      inherited_accessor(*ATTRIBUTES)

      strip_trailing_separator(*ATTRIBUTES.select{|a| a.to_s =~ /dir|path/})

      ARRAY_ATTRIBUTES.each do |array_attr|
        inherited_array(array_attr, ARRAY_ATTRIBUTE_OPTIONS.fetch(array_attr, {}))
      end

      def initialize(name, attr_hash = nil)
        raise "I need a name!" unless name && (name.is_a?(String) || name.is_a?(Symbol))
        @name = name
        set_all(attr_hash) if attr_hash
        self.top_level = self
      end

      def set_all(attr_hash)
        attr_hash.each do |a, v|
          if self.respond_to?("#{a}=")
            self.send("#{a}=", v)
          end
        end
      end

      alias http_path_without_error= http_path=
      def http_path=(path)
        if path == :relative
          raise ArgumentError, ":relative is no longer a valid value for http_path. Please set relative_assets = true instead."
        end
        self.http_path_without_error = path
      end

      def add_import_path(*paths)
        paths.map!{|p| defined?(Pathname) && Pathname === p ? p.to_s : p}
        # The @added_import_paths variable works around an issue where
        # the additional_import_paths gets overwritten during parse
        @added_import_paths ||= []
        @added_import_paths += paths
        paths.each do |p|
          self.additional_import_paths << p unless additional_import_paths.include?(p)
        end
      end


      # Add a location where sass, image, and font assets can be found.
      # @see AssetCollection#initialize for options
      def add_asset_collection(options)
        @url_resolver = nil
        asset_collections << AssetCollection.new(options)
      end

      # When called with a block, defines the asset host url to be used.
      # The block must return a string that starts with a protocol (E.g. http).
      # The block will be passed the root-relative url of the asset.
      # When called without a block, returns the block that was previously set.
      def asset_host(&block)
        @set_attributes ||= {}
        if block_given?
          @set_attributes[:asset_host] = true
          @asset_host = block
        else
          if @asset_host
            @asset_host
          elsif inherited_data.respond_to?(:asset_host)
            inherited_data.asset_host
          end
        end
      end

      # When called with a block, defines the cache buster strategy to be used.
      # If the block returns nil or a string, then it is appended to the url as a query parameter.
      # In this case, the returned string must not include the starting '?'.
      # The block may also return a hash with :path and/or :query values and it
      # will replace the original path and query string with the busted values returned.
      # The block will be passed the root-relative url of the asset.
      # If the block accepts two arguments, it will also be passed a File object
      # that points to the asset on disk -- which may or may not exist.
      # When called without a block, returns the block that was previously set.
      #
      # To disable the asset cache buster:
      #
      #     asset_cache_buster :none
      def asset_cache_buster(simple = nil, &block)
        @set_attributes ||= {}
        if block_given?
          @set_attributes[:asset_cache_buster] = true
          @asset_cache_buster = block
        elsif !simple.nil?
          if simple == :none
            @set_attributes[:asset_cache_buster] = true
            @asset_cache_buster = Proc.new {|_,_| nil}
          else
            raise ArgumentError, "Unexpected argument: #{simple.inspect}"
          end
        else
          if set?(:asset_cache_buster)
            @asset_cache_buster
          elsif inherited_data.respond_to?(:asset_cache_buster)
            inherited_data.asset_cache_buster
          end
        end
      end

      def watch(glob, &block)
        @watches ||= []
        @watches << Watch.new(glob, &block)
      end

      def watches
        if defined?(@watches)
          @watches
        elsif inherited_data.respond_to?(:watches)
          inherited_data.watches
        else
          []
        end
      end

      # Require a compass plugin and capture that it occured so that the configuration serialization works next time.
      def require(lib)
        (self.required_libraries ||= []) << lib
        super
      end

      def load(framework_dir)
        (self.loaded_frameworks ||= []) << framework_dir
        Compass::Frameworks.register_directory framework_dir
      end

      # Finds all extensions within a directory and registers them.
      def discover(frameworks_dir)
        (self.framework_path ||= []) << frameworks_dir
        Compass::Frameworks.discover frameworks_dir
      end

      def relative_assets?
        # the http_images_path is deprecated, but here for backwards compatibility.
        relative_assets
      end

      def url_resolver
        return @url_resolver if @url_resolver
        if top_level == self
          @url_resolver = Compass::Core::AssetUrlResolver.new(asset_collections.to_a, self)
        else
          top_level.url_resolver
        end
      end

      def sprite_resolver
        return @sprite_resolver if @sprite_resolver
        if top_level == self
          sprite_collections = asset_collections.to_a
          sprite_collections += sprite_load_path.to_a.map do |slp|
            AssetCollection.new(
              :root_path => slp,
              :http_path => http_images_path,
              :images_dir => "."
            )
          end
          @sprite_resolver = Compass::Core::AssetUrlResolver.new(sprite_collections, self)
        else
          top_level.url_resolver
        end
      end
    end
  end
end
