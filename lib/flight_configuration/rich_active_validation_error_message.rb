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
  module RichActiveValidationErrorMessage
    def self.rich_error_message(config)
      return nil if config.nil?
      # Variable definitions
      sources = config.__sources__
      initial = { file: {}, env: [], default: [], missing: [] }

      # Group errors into their sources
      sections = config.errors.reduce(initial) do |memo, error|
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
      config.class.config_files.reverse.map(&:to_s).each do |path|
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

      # Return the error
      # NOTE: The first newline needs to be removed
      msg[1..-1]
    end

    def rich_error_message
      FlightConfiguration::RichActiveValidationError.rich_error_message(self)
    end
  end
end
