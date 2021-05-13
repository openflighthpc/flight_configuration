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
  # Provides convention over the mechanism provided in `BaseDSL`.
  #
  # The application embedding `DSL` is expected to define a `Flight` module
  # containing the following module methods.
  #
  # * `Flight.root`:  Return the (String) path to the "root" of the filesystem.
  #
  #   When deployed as part of the openflighthpc packages, this is likely to
  #   be the value of the `flight_ROOT` environment variable, often
  #   `/opt/flight`.  During development, this is likely to be the root of the
  #   applications source code checkout.
  #
  #   Relative paths for configuration files are relative to this path.  E.g.,
  #   the configuration file at the relative path `etc/my-app.yaml` might
  #   resolve to either `/opt/flight/etc/my-app.yaml` or
  #   `/home/fligth/code/my-app/etc/my-app.yaml`, depending on the value of
  #   `Flight.root`.
  #
  # * `Flight.env`: Return the (String) environment name.
  #
  #   Typically, `production` or `development`.  Used to determine which
  #   configuration files are loaded.
  module DSL
    include BaseDSL

    def application_name(name=nil)
      @application_name ||= name
      if @application_name.nil?
        raise Error, 'The application_name has not been defined!'
      end
      @application_name
    end

    def root_path(*_)
      super Flight.root
    end

    def config_files(*_)
      @config_files ||= [
        root_path.join("etc/#{application_name}.yaml"),
        root_path.join("etc/#{application_name}.#{Flight.env}.yaml"),
        root_path.join("etc/#{application_name}.local.yaml"),
        root_path.join("etc/#{application_name}.#{Flight.env}.local.yaml"),
      ]
      super
    end

    def env_var_prefix(*_)
      @env_var_prefix ||=
        begin
          parts = application_name.split(/[_-]/)
          parts.shift if parts.first == 'flight'
          ['flight', parts.map(&:upcase)].join('_')
        end
      super
    end
  end
end
