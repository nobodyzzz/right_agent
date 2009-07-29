#
# Copyright (c) 2009 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RightScale

  # Apply each method call to all registered targets
  class Multiplexer

    # Initialize multiplexer targets
    #
    # === Parameters
    # targets<Object>:: Targets that should receive the method calls
    def initialize(*targets)
      @targets = targets || []
    end

    # Add object to list of multiplexed targets
    #
    # === Parameters
    # target<Object>:: Add target to list of multiplexed targets
    #
    # === Return
    # @targets<Array>:: List of targets
    def add(target)
      @targets << target unless @targets.include?(target)
      @targets
    end

    # Remove object from list of multiplexed targets
    #
    # === Parameters
    # target<Object>:: Remove target from list of multiplexed targets
    #
    # === Return
    # @targets<Array>:: List of targets
    def remove(target)
      @targets.delete_if { |t| t == target }
      @targets
    end

    # Forward any method invokation to targets
    #
    # === Parameters
    # m<Symbol>:: Method that should be multiplexed
    # args<Array>:: Arguments
    #
    # === Return
    # res<Array>:: Array of results in the same order as the targets
    def method_missing(m, *args)
      res = @targets.inject([]) { |res, t| res << t.__send__(m, *args) }
    end

  end
end