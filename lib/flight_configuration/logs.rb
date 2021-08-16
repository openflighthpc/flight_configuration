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
  class Logs
    def initialize
      @logs = []
    end

    def file_loaded(file)
      info "Loaded #{file}"
    end

    def file_not_found(file)
      debug "Not found #{file}"
    end

    def set_from_source(key, source)
      if source.type == :default
        debug "Config '#{key}' set to default"
      elsif source.recognized?
        type = source.type == :env ? 'env var ' : ''
        debug "Config '#{key}' loaded from #{type}#{source.source}"
      else
        warn "Ignoring unrecognized config '#{key}' (source: #{source.source})"
      end
    end

    def debug(msg)
      @logs << [:debug, msg]
    end

    def info(msg)
      @logs << [:info, msg]
    end

    def warn(msg)
      @logs << [:warn, msg]
    end

    def error(msg, &block)
      @logs << [:error, msg, block]
    end

    def log_with(logger)
      @logs.each do |type, msg, block|
        if block
          logger.send(type, "FC: #{msg}", &block)
        else
          logger.send(type, "FC: #{msg}")
        end
      end
      @logs.clear
    end
  end
end
