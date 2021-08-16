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
  module FallbackValidator
    def self.validate(config)
      errors = []
      config.__sources__.each do |_, source|
        if source.attribute[:required] && source.value.nil?
          errors << [:missing, source.key]
        end
        unless source.transform_valid?
          errors << [:transform, source.key]
        end
      end
      errors << :invalid if config.respond_to?(:valid?) && !config.valid?
      return errors
    end

    def self.validate!(config)
      errors = validate(config)
      return if errors.empty?
      strings = errors.map do |type, *args|
        case type
        when :missing
          "The required config '#{args.first}' is missing!"
        when :transform
          "Failed to coerce attribute '#{args.first}'!"
        else
          type.to_s # NOTE: This should not be used in practice
        end
      end
      raise Error, <<~ERROR.chomp
        Can not continue as the following errors occurred when validating the config:
        #{strings.map { |s| " * #{s}" }.join("\n")}
      ERROR
    end
  end
end
