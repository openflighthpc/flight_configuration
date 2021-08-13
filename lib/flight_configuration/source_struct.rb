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
  # NOTE: The type specifies if it came from the :env or :file
  SourceStruct = Struct.new(:key, :source, :type, :value, :config) do
    def attribute
      @attribute ||= config.class.attributes[key] || {}
    end

    def transformable?
      transformed_value if @transformable.nil?
      @transformable
    end

    def recognized?
      !attribute.empty?
    end

    def transformed_value
      return @transformed_value unless @transformable.nil?
      @transformable = true
      transform = attribute[:transform]
      @transformed_value = if transform.nil?
        value
      elsif transform.respond_to?(:call)
        transform.call(value)
      else
        value.send(transform)
      end
    rescue
      config.__logs__.error("Failed to coerce attribute: #{key}")
      config.__logs__.debug $!.full_message
      @transformable = false
    end
  end
end
