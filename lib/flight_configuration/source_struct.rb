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

module FlightConfiguration
  # Stores a reference to where a particular key came from
  #
  # The type specifies if it came from the :env, :file or the :default.
  class SourceStruct
    attr_reader :key, :source, :type, :value

    def initialize(key, source, type, value, config)
      @key = key
      @source = source
      @type = type
      @value = value
      @config = config
    end

    def attribute
      @attribute ||= @config.class.attributes[key] || {}
    end

    def transform_valid?
      transformed_value unless defined?(@transform_valid)
      @transform_valid
    end

    def recognized?
      !attribute.empty?
    end

    def transformed_value
      if defined?(@transformed_value)
        return @transformed_value
      end

      transform = attribute[:transform]
      @transformed_value = if transform.nil?
        value
      elsif transform.respond_to?(:call)
        transform.call(value)
      else
        value.send(transform)
      end
    rescue => e
      @config.__logs__.error("Failed to coerce attribute: #{key}") { e.full_message }
      @transform_valid = false
      nil
    else
      @transform_valid = true
      @transformed_value
    end

    def value
      return @value unless type == :default && !@default_set

      @default_set = true
      default = attribute[:default]
      @value = if default.respond_to?(:call) && default.arity == 0
        default.call
      elsif default.respond_to?(:call)
        default.call(@config)
      else
        default
      end
    end
  end
end
