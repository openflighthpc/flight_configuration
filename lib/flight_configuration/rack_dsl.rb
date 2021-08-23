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
  # DEPRECATED: Applications should be ported to use `DSL`.
  #
  # Porting an application to `DSL` involves:
  #  * defining a `Flight` module; details in `DSL` documentation.
  #  * removing calls to `root_path`.
  #  * ensuring the additional configuration files don't cause issues.

  # Provides convention over the mechanism provided in `BaseDSL`.  The
  # convention is suitable for a Rack app, hence the name.
  module RackDSL
    extend Concern
    include BaseDSL

    class_methods do
      def application_name(name=nil)
        @application_name ||= name
        if @application_name.nil?
          raise Error, 'The application_name has not been defined!'
        end
        @application_name
      end

      def config_files(*_)
        @config_files ||= begin
          if ENV['RACK_ENV'] == 'production'
            [root_path.join("etc/#{application_name}.yaml")]
          else
            [root_path.join("etc/#{application_name}.#{ENV['RACK_ENV']}.yaml"),
             root_path.join("etc/#{application_name}.#{ENV['RACK_ENV']}.local.yaml")]
          end
        end
        super
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

      def env_var_prefix(*_)
        @env_var_prefix ||=
          begin
            parts = application_name.split(/[_-]/)
            flight_part = (parts.first == 'flight' ? [parts.shift] : [])
            parts.map!(&:upcase)
            [*flight_part, *parts].join('_')
          end
        super
      end
    end
  end
end
