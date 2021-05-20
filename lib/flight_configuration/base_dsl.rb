#==============================================================================
# Copyright (C) 2021-present Alces Flight Ltd.
#
# This file is part of FlightConfiguration.
#
# This program and the accompanying materials are made available under
# the terms of the Eclipse Public License 2.0 which is available at
# <https://www.eclipse.org/legal/epl-2.0>, or alternative license
# terms made available by Alces Flight Ltd - please direct inquiries
# about licensing to licensing@alces-flight.com.
#
# FlightConfiguration is distributed in the hope that it will be useful, but
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
# IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS
# OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A
# PARTICULAR PURPOSE. See the Eclipse Public License 2.0 for more
# details.
#
# You should have received a copy of the Eclipse Public License 2.0
# along with FlightConfiguration. If not, see:
#
#  https://opensource.org/licenses/EPL-2.0
#
# For more information on FlightConfiguration, please visit:
# https://github.com/openflighthpc/flight_configuration
#==============================================================================

require 'pathname'
require 'yaml'

module FlightConfiguration
  class Error < StandardError; end

  module DeepStringifyKeys
    def self.stringify(object)
      case object
      when Hash
        object.each_with_object(object.class.new) do |(key, value), memo|
          memo[key.to_s] = self.stringify(value)
        end
      when Array
        object.map { |v| self.stringify(v) }
      else
        object
      end
    end
  end

  # Stores a reference to where a particular key came from
  # NOTE: The type specifies if it came from the :env or :file
  SourceStruct = Struct.new(:key, :source, :type, :value)

  module BaseDSL
    def config_files(*paths)
      @config_files ||= []
      unless paths.empty?
        @config_files.push(*paths.map { |p| File.expand_path(p, root_path) })
      end
      if @config_files.empty?
        raise Error, 'No config paths have been defined!'
      else
        @config_files
      end
    end

    def root_path(path = nil)
      case path
      when String
        @root_path = Pathname.new(path)
      when Pathname
        @root_path = path
      end
      if @root_path.nil?
        raise Error, "The root_path has not been defined!"
      end
      @root_path
    end

    def env_var_prefix(prefix = nil)
      @env_var_prefix = prefix if prefix
      if @env_var_prefix.nil?
        raise Error, "The env_var_prefix has not been defined!"
      end
      @env_var_prefix
    end

    def attributes
      @attributes ||= {}
    end

    def attribute(name, env_var: true, required: true, default: nil, **opts)
      name = name.to_s
      transform = if opts.key? :transform
                    opts[:transform]
                  elsif default.is_a? String
                    :to_s
                  elsif default.is_a? Integer
                    ->(int) { Integer(int) }
                  end

      # Define the attribute
      attributes[name] = {
        name: name.to_s,
        env_var: env_var,
        default: default,
        required: required,
        transform: transform
      }
      attr_accessor name.to_s

      # Define the accessor that returns the original value
      define_method("_#{name.to_s}") do
        @__sources__ ||= {}
        @__sources__[name]&.value
      end
    end

    def load
      new.tap do |config|
        config.instance_variable_set(:@__sources__, {})
        merge_sources.each do |key, source|
          required = attributes.fetch(key, {})[:required]
          if source.value.nil? && required
            raise Error, "The required config has not been provided: #{key}"
          else
            config.instance_variable_get(:@__sources__)[key] = source
            config.send("#{key}=", transform(key, source.value))
          end
        end

        # Attempt to valildate the config
        validate!(config)
      end
    rescue => e
      raise e, "Cannot load configuration:\n#{e.message}", e.backtrace
    end

    def merge_sources
      {}.tap do |sources|
        # Apply the env vars
        from_env_vars.each do |key, value|
          sources[key] = SourceStruct.new(key, "#{env_var_prefix}_#{key}", :env, value)
        end

        # Apply the configs
        config_files.reverse.each do |file|
          hash = from_config_file(file) || {}
          hash.each do |key, value|
            next if sources.key?(key)
            # Ensure the file is a string and not pathname
            sources[key] = SourceStruct.new(key, file.to_s, :file, value)
          end
        end

        # Apply the defaults
        defaults.each do |key, value|
          next if sources.key?(key)
          sources[key] = SourceStruct.new(key, nil, :default, value)
        end
      end
    end

    def defaults
      hash = attributes.values.reduce({}) do |accum, attr|
        key = attr[:name]
        default = attr[:default]
        accum[key] = default.respond_to?(:call) ? default.call : default
        accum
      end
      DeepStringifyKeys.stringify(hash)
    end

    def relative_to(base_path)
      ->(value) { File.expand_path(value, base_path) }
    end

    def from_config_file(config_file)
      return {} unless File.exists?(config_file)
      yaml =
        begin
          YAML.load_file(config_file)
        rescue ::Psych::SyntaxError
          raise "YAML syntax error occurred while parsing #{config_file}. " \
            "Please note that YAML must be consistently indented using spaces. Tabs are not allowed. " \
            "Error: #{$!.message}"
        end
      FlightConfiguration::DeepStringifyKeys.stringify(yaml) || {}
    end

    private

    def from_env_vars
      envs = attributes.values.reduce({}) do |accum, attr|
        if attr[:env_var]
          env_var = "#{env_var_prefix}_#{attr[:name]}"
          unless ENV[env_var].nil?
            accum[attr[:name]] = ENV[env_var]
          end
        end
        accum
      end
      DeepStringifyKeys.stringify(envs)
    end

    def transform(key, value)
      config_definition = attributes.fetch(key.to_s, {})
      transform = config_definition[:transform]
      if transform.nil?
        value
      elsif transform.respond_to?(:call)
        transform.call(value)
      else
        value.send(transform)
      end
    end

    def validate!(config)
      # Attempt to use the validate! method if the errors struct isn't defined
      if config.respond_to?(:validate!) && !config.respond_to?(:errors)
        config.validate!
        return
      end

      # Ignore configs which are valid or do not implement valid?
      return unless config.respond_to?(:valid?)
      return if config.valid?

      # Emit a generic warning for class which do not have errors
      raise Error, <<~ERROR unless config.respond_to?(:errors)
        Failed to validate the application's configuration
      ERROR

      # Group the errors into their sources
      sources = config.instance_variable_get(:@__sources__) || {}
      initial = { file: {}, env: [], default: [], missing: [] }
      sections = config.errors.reduce(initial) do |memo, error|
        source = sources[error.attribute.to_s]
        case source&.type
        when NilClass
          memo[:missing] << error
        when :file
          memo[:file][source.source] ||= []
          memo[:file][source.source] << error
        else
          memo[source.type] << error
        end
        memo
      end

      # Generate the error message
      msg = "Can not continue as the config is invalid!"

      # Display generic errors which do not correspond with any attributes
      unless sections[:missing].empty?
        msg << "\n\nThe following errors have occurred:"
        sections[:missing].each do |error|
          msg << "\n* #{error.full_message}"
        end
      end

      # Display the environment variables
      unless sections[:env].empty?
        msg << "\n\nThe following environment variable(s) are invalid:"
        sections[:env].each do |error|
          env = sources[error.attribute.to_s].source
          msg << "\n* #{env}: #{error.message}"
        end
      end

      # Display errors from a config file
      config_files.reverse.map(&:to_s).each do |path|
        next if sections[:file][path].blank?
        msg << "\n\nThe following config contains invalid attribute(s): #{path}"
        sections[:file][path].each do |error|
          msg << "\n* #{error.attribute}: #{error.message}"
        end
      end

      # Display errors associated with the defaults
      # NOTE: *Technically* they could error for any validation reason, but the primary
      # use case is they are missing. A sensible default can not be provided in all cases,
      # so instead the user should be prompted to provide them.
      unless sections[:default].empty?
        msg << "\n\nThe following required attribute(s) have not been set:"
        sections[:default].each do |error|
          msg << "\n* #{error.attribute}"
        end
      end

      # Raise the error
      raise Error, msg
    end
  end
end