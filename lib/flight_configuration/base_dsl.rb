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
  SourceStruct = Struct.new(:key, :source, :type, :value, :unrecognized)

  # NOTE: This inheritance hierarchy is becoming unwieldy and follows
  #       a extend/include InstanceMethods anti-pattern
  #
  #       Consider porting ActiveSupport::Concerns
  module BaseDSL
    # NOTE: Because the DSL 'extends' a class, an InstanceMethods module is included
    #       This is in contrast to the include/extend ClassMethods pattern
    module InstanceMethods
      def __sources__
        @__sources__ ||= {}
      end

      def __logs__
        @__logs__ ||= Logs.new
      end
    end

    # The following propagates the DSLClassMethods down included modules without
    # using ActiveSupport::Concerns
    module DSLClassMethods
      # When including the BaseDSL into a new *DSL module, extend the new *DSL
      # with the original ClassMethods. This propagates the ClassMethods
      def included(base)
        base.extend(FlightConfiguration::BaseDSL::DSLClassMethods)
      end

      # When extending a class with a *DSL, define the instance methods
      def extended(base)
        base.include FlightConfiguration::BaseDSL::InstanceMethods
      end
    end

    # NOTE: The following does not trigger the 'ClassMethods#extended' instance method,
    #       Instead it defines it as a class method
    extend DSLClassMethods

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
      define_method("#{name.to_s}_before_type_cast") do
        __sources__[name]&.value
      end
    end

    def load
      new.tap do |config|
        merge_sources(config).each do |key, source|
          required = attributes.fetch(key, {})[:required]
          if source.value.nil? && required
            if active_errors?
              config.errors.add(key, :required, message: 'is required')
            else
              raise Error, "The required config has not been provided: #{key}"
            end
          elsif config.respond_to?("#{key}=")
            config.send("#{key}=", transform(config, key, source.value))
          else
            source.unrecognized = true
          end
          config.__logs__.set_from_source(key, source)
        end

        # Attempt to validate the config
        validate_config(config)
      end
    rescue => e
      raise e, "Cannot continue as the configuration is invalid:\n#{e.message}", e.backtrace
    end

    # NOTE: Both the logs and inbuilt required mechanism rely on 'defaults'
    #       containing each key within 'attributes'. Failure to do so may
    #       lead to nil errors.
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

    private

    def merge_sources(config)
      config.__sources__.tap do |sources|
        # Pre-populate the keys to give them a defined order in the logs
        attributes.each { |key, _| sources[key] = nil }

        # Apply the env vars
        from_env_vars.each do |key, value|
          sources[key] = SourceStruct.new(key, "#{env_var_prefix}_#{key}", :env, value)
        end

        # Apply the configs
        config_files.reverse.each do |file|
          hash = from_config_file(file) || {}
          if File.exists?(file)
            config.__logs__.file_loaded(file)
          else
            config.__logs__.file_not_found(file)
          end
          hash.each do |key, value|
            next if sources[key]
            # Ensure the file is a string and not pathname
            sources[key] = SourceStruct.new(key, file.to_s, :file, value)
          end
        end

        # Apply the defaults
        defaults.each do |key, value|
          next if sources[key]
          sources[key] = SourceStruct.new(key, nil, :default, value)
        end
      end
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

    # Checks if ActiveValidation/ ActiveErrors can be used
    # Requires the 'errors' and 'valid?' methods
    def active_errors?
      @active_errors ||= (self.instance_methods & [:errors, :valid?]).length == 2
    end

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

    def transform(config, key, value)
      config_definition = attributes.fetch(key.to_s, {})
      transform = config_definition[:transform]
      if transform.nil?
        value
      elsif transform.respond_to?(:call)
        transform.call(value)
      else
        value.send(transform)
      end
    rescue
      # NOTE: Ideally the error would be logged, however this can't be done
      #       without forming a recursive loop
      if active_errors?
        config.errors.add(key.to_sym, type: :transform, message: 'failed to coerce the data type')
      else
        raise Error, "Failed to coerce attribute: #{key}"
      end
    end

    # The 'validate' method is already used by ActiveValidation, so validate_config is used instead
    def validate_config(config)
      # Use active errors instead
      if active_errors?
        validate_active_errors(config)

      # Attempt to use validate! instead
      elsif config.respond_to?(:validate!)
        config.validate!

      # Otherwise raise a generic error if invalid
      elsif config.respond_to?(:valid?) && !valid?
        raise Error, <<~ERROR
          Failed to validate the application's configuration
        ERROR
      end
    end

    def validate_active_errors(config)
      # Get the current state of the errors and validate
      current_errors = config.errors.dup
      return if config.valid? && current_errors.empty?

      # Variable definitions
      sources = config.__sources__
      initial = { file: {}, env: [], default: [], missing: [] }
      all_errors = [current_errors, config.errors]

      # Group errors into their sources
      sections = all_errors.reduce(initial) do |set_memo, errors|
        errors.reduce(set_memo) do |memo, error|
          # Key standardization may not be required, particularly if using ActiveValidation
          # However it has been retained due to the loose coupling
          # Consider removing if hard coupling is introduced
          key = error.attribute.to_s.sub(/_before_type_cast\Z/, '')
          source = sources[key]
          case source&.type
          when NilClass
            memo[:missing] << [key, error]
          when :file
            memo[:file][source.source] ||= []
            memo[:file][source.source] << [key, error]
          when :env
            memo[source.type] << [source.source, error]
          else
            memo[source.type] << [key, error]
          end
          memo
        end
        set_memo
      end

      # Generate the error message
      msg = ""

      # Display generic errors which do not correspond with any attributes
      unless sections[:missing].empty?
        msg << "\n\nThe following errors have occurred:"
        sections[:missing].each do |_, error|
          msg << "\n* #{error.full_message}"
        end
      end

      # Display the environment variables
      unless sections[:env].empty?
        msg << "\n\nThe following environment variable(s) are invalid:"
        sections[:env].each do |env, error|
          msg << "\n* #{env}: #{error.message}"
        end
      end

      # Display errors from a config file
      config_files.reverse.map(&:to_s).each do |path|
        next if sections[:file][path].blank?
        msg << "\n\nThe following config contains invalid attribute(s): #{path}"
        sections[:file][path].each do |key, error|
          msg << "\n* #{key}: #{error.message}"
        end
      end

      # Display errors associated with the defaults
      # NOTE: *Technically* they could error for any validation reason, but the primary
      # use case is they are missing. A sensible default can not be provided in all cases,
      # so instead the user should be prompted to provide them.
      unless sections[:default].empty?
        msg << "\n\nThe following required attribute(s) have not been set:"
        sections[:default].map { |k, _| k }.uniq.each do |attr|
          msg << "\n* #{attr}"
        end
      end

      # Raise the error
      # NOTE: The first newline needs to be removed
      raise Error, msg[1..-1]
    end
  end
end
