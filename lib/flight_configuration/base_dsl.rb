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
  module BaseDSL
    extend Concern

    class_methods do
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
          __sources__[name]&.value_before_type_cast
        end

        # Defines the default ActiveValidation validators (when applicable)
        if active_validation?
          validates(name, presence: true, allow_blank: true) if required
          validate do
            next if __sources__[name].transform_valid?
            @errors.add name, type: :transform,
              message: 'failed to coerce the data type'
          end
        end
      end

      def build
        new.tap do |config|
          # Set the attributes
          merge_sources(config).each do |key, source|
            config.send("#{key}=", source.value) if source.recognized?
            config.__logs__.set_from_source(key, source)
          end
        end
      end

      def load
        build.tap do |config|
          if active_validation?
            unless config.valid?
              msg = RichActiveValidationErrorMessage.rich_error_message(config)
              raise Error, msg
            end
          else
            config.validate!
          end
        end
      end

      def relative_to(base_path)
        ->(value) { File.expand_path(value, base_path) }
      end

      private

      def active_validation?
        return @active_validation unless @active_validation.nil?
        @active_validation = ancestors.find do |klass|
          klass.to_s == 'ActiveModel::Validations'
        end
      end

      def merge_sources(config)
        config.__sources__.tap do |sources|
          # Pre-populate the keys to give them a defined order in the logs
          attributes.each { |key, _| sources[key] = nil }

          # Apply the env vars
          from_env_vars.each do |key, value|
            sources[key] = SourceStruct.new(key, "#{env_var_prefix}_#{key}", :env, value, config)
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
              sources[key] = SourceStruct.new(key, file.to_s, :file, value, config)
            end
          end

          # Apply the defaults
          attributes.values.each do |attr|
            key = attr[:name].to_s
            next if sources[key]
            sources[key] = SourceStruct.new(key, nil, :default, attr[:default], config)
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
    end

    def __sources__
      @__sources__ ||= {}
    end

    def __logs__
      @__logs__ ||= Logs.new
    end

    def respond_to_missing?(method, *args)
      return true if [:validate, :validate!].include? method
      super
    end

    # Support the validate/validate! methods without defining them
    # This allows ActiveValidation to redefine it
    def method_missing(method, *args)
      case method
      when :validate
        FallbackValidator.validate(self)
      when :validate!
        FallbackValidator.validate!(self)
      else
        super
      end
    end
  end
end
