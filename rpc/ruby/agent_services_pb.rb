# Generated by the protocol buffer compiler.  DO NOT EDIT!
# Source: agent.proto for package 'jiji.rpc'

require 'grpc'
require 'agent_pb'

module Jiji
  module Rpc
    module AgentService
      class Service

        include GRPC::GenericService

        self.marshal_class_method = :encode
        self.unmarshal_class_method = :decode
        self.service_name = 'jiji.rpc.AgentService'

        rpc :NextTick, NextTickRequest, Google::Protobuf::Empty
        rpc :Register, AgentSource, Google::Protobuf::Empty
        rpc :Unregister, AgentSourceName, Google::Protobuf::Empty
        rpc :GetAgentClasses, Google::Protobuf::Empty, AgentClasses
        rpc :CreateAgentInstance, AgentCreationRequest, AgentCreationResult
        rpc :GetAgentState, GetAgentStateRequest, AgentState
      end

      Stub = Service.rpc_stub_class
    end
  end
end
