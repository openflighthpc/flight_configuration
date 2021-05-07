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
                    :to_i
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
    end

    def load
      merged = defaults.merge(from_config_files).merge(from_env_vars)
      new.tap do |config|
        merged.each do |key, value|
          required = attributes.fetch(key, {})[:required]
          if value.nil? && required
            raise Error, "The required config has not been provided: #{key}"
          else
            config.send("#{key}=", transform(key, value))
          end
        end
      end
    rescue => e
      raise e, "Cannot load configuration:\n#{e.message}", e.backtrace
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

    def from_config_files
      config_files.reduce({}) do |accum, config_file|
        accum.merge(from_config_file(config_file) || {})
      end
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
  end
end
