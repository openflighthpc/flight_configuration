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
  module RackDSL
    include DSL

    def application_name(name = nil)
      @application_name ||= name
      if @application_name.nil?
        raise Error, 'The application_name has not been defined!'
      end
      @application_name
    end

    def config_files(*_)
      @config_files ||= begin
        if ENV['RACK_ENV'] == 'production'
          ["etc/#{application_name}.yaml"]
        else
          ["etc/#{application_name}.#{ENV['RACK_ENV']}.yaml",
           "etc/#{application_name}.#{ENV['RACK_ENV']}.local.yaml"]
        end
      end
      super
    end

    def env_var_prefix(*_)
      @env_var_prefix ||= application_name.upcase.gsub('-', '_')
      super
    end
  end
end
