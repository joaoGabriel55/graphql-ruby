# frozen_string_literal: true
require "spec_helper"

describe GraphQL::Schema::Mutation do
  let(:mutation) { Jazz::AddInstrument }
  after do
    Jazz::Models.reset
  end

  it "Doesn't override !" do
    assert_equal false, !mutation
  end

  describe "definition" do
    it "passes along description" do
      assert_equal "Register a new musical instrument in the database", Jazz::Mutation.get_field("addInstrument").description
      assert_equal "Autogenerated return type of AddInstrument.", mutation.payload_type.description
    end
  end

  describe "argument prepare" do
    it "calls methods on the mutation, uses `as:`" do
      query_str = "mutation { prepareInput(input: 4) }"
      res = Jazz::Schema.execute(query_str)
      assert_equal 16, res["data"]["prepareInput"], "It's squared by the prepare method"
    end
  end

  describe "a derived field" do
    it "has a reference to the mutation" do
      test_setup = self

      t = Class.new(GraphQL::Schema::Object) do
        field :x, mutation: test_setup.mutation
      end
      f = t.get_field("x")
      assert_equal mutation, f.mutation

      # Make sure it's also present in the schema
      f2 = Jazz::Schema.find("Mutation.addInstrument")
      assert_equal mutation, f2.mutation
    end
  end

  describe ".payload_type" do
    it "has a reference to the mutation" do
      assert_equal mutation, mutation.payload_type.mutation
    end
  end

  describe ".object_class" do
    it "can override & inherit the parent class" do
      obj_class = Class.new(GraphQL::Schema::Object)
      mutation_class = Class.new(GraphQL::Schema::Mutation) do
        object_class(obj_class)
      end
      mutation_subclass = Class.new(mutation_class)

      assert_equal(GraphQL::Schema::Object, GraphQL::Schema::Mutation.object_class)
      assert_equal(obj_class, mutation_class.object_class)
      assert_equal(obj_class, mutation_subclass.object_class)
    end
  end

  describe ".argument_class" do
    it "can override & inherit the parent class" do
      arg_class = Class.new(GraphQL::Schema::Argument)
      mutation_class = Class.new(GraphQL::Schema::Mutation) do
        argument_class(arg_class)
      end

      mutation_subclass = Class.new(mutation_class)

      assert_equal(GraphQL::Schema::Argument, GraphQL::Schema::Mutation.argument_class)
      assert_equal(arg_class, mutation_class.argument_class)
      assert_equal(arg_class, mutation_subclass.argument_class)
    end
  end

  describe "evaluation" do
    it "runs mutations" do
      query_str = <<-GRAPHQL
      mutation {
        addInstrument(name: "trombone", family: BRASS) {
          instrument {
            name
            family
          }
          entries {
            name
          }
          ee
        }
      }
      GRAPHQL

      response = Jazz::Schema.execute(query_str)
      assert_equal "Trombone", response["data"]["addInstrument"]["instrument"]["name"]
      assert_equal "BRASS", response["data"]["addInstrument"]["instrument"]["family"]
      errors_class = "GraphQL::Execution::Interpreter::ExecutionErrors"
      assert_equal errors_class, response["data"]["addInstrument"]["ee"]
      assert_equal 7, response["data"]["addInstrument"]["entries"].size
    end

    it "accepts a list of errors as a valid result" do
      query_str = "mutation { returnsMultipleErrors { dummyField { name } } }"

      response = Jazz::Schema.execute(query_str)
      assert_equal 2, response["errors"].length, "It should return two errors"
    end

    it "raises a mutation-specific invalid null error" do
      query_str = "mutation { returnInvalidNull { int } }"
      response = Jazz::Schema.execute(query_str)
      assert_equal ["Cannot return null for non-nullable field ReturnInvalidNullPayload.int"], response["errors"].map { |e| e["message"] }
      error = response.query.context.errors.first
      assert_instance_of Jazz::ReturnInvalidNull.payload_type::InvalidNullError, error
      assert_equal "Jazz::ReturnInvalidNull::ReturnInvalidNullPayload::InvalidNullError", error.class.inspect
    end
  end

  describe ".null" do
    it "overrides whether or not the field can be null" do
      non_nullable_mutation_class = Class.new(GraphQL::Schema::Mutation) do
        graphql_name "Thing1"
        null(false)
      end

      nullable_mutation_class = Class.new(GraphQL::Schema::Mutation) do
        graphql_name "Thing2"
        null(true)
      end

      default_mutation_class = Class.new(GraphQL::Schema::Mutation) do
        graphql_name "Thing3"
      end

      example_mutation_type = Class.new(GraphQL::Schema::Object) do
        field :non_nullable_mutation, mutation: non_nullable_mutation_class
        field :nullable_mutation, mutation: nullable_mutation_class
        field :default_mutation, mutation: default_mutation_class
      end

      refute example_mutation_type.get_field("defaultMutation").type.non_null?
      refute example_mutation_type.get_field("nullableMutation").type.non_null?
      assert example_mutation_type.get_field("nonNullableMutation").type.non_null?
    end

    it "should inherit and override in subclasses" do
      base_mutation = Class.new(GraphQL::Schema::Mutation) do
        null(false)
      end

      inheriting_mutation = Class.new(base_mutation) do
        graphql_name "Thing"
      end

      override_mutation = Class.new(base_mutation) do
        graphql_name "Thing2"
        null(true)
      end

      f1 = GraphQL::Schema::Field.new(name: "f1", resolver_class: inheriting_mutation)
      assert_equal true, f1.type.non_null?
      f2 = GraphQL::Schema::Field.new(name: "f2", resolver_class: override_mutation)
      assert_equal false, f2.type.non_null?
    end
  end

  it "warns once for possible conflict methods" do
    expected_warning = "X's `field :module` conflicts with a built-in method, use `hash_key:` or `method:` to pick a different resolve behavior for this field (for example, `hash_key: :module_value`, and modify the return hash). Or use `method_conflict_warning: false` to suppress this warning.\n"
    assert_output "", expected_warning do
      # This should warn:
      mutation = Class.new(GraphQL::Schema::Mutation) do
        graphql_name "X"
        field :module, String
      end
      # This should not warn again, when generating the payload type with the same fields:
      mutation.payload_type
    end

    assert_output "", "" do
      mutation = Class.new(GraphQL::Schema::Mutation) do
        graphql_name "X"
        field :module, String, hash_key: :module_value
      end
      mutation.payload_type
    end
  end

  class InterfaceMutationSchema < GraphQL::Schema
    class SignIn < GraphQL::Schema::Mutation
      argument :login, String
      argument :password, String
      field :success, Boolean, null: false
      def resolve(login:, password:)
        { success: login == password }
      end
    end

    module Auth
      include GraphQL::Schema::Interface
      field :sign_in, mutation: SignIn
    end

    class Mutation < GraphQL::Schema::Object
      implements Auth
    end

    mutation(Mutation)
    query(Mutation)
  end

  it "works when mutations are added via interfaces" do
    result = InterfaceMutationSchema.execute("mutation { signIn(login: \"abc\", password: \"abc\") { success } }")
    assert_equal true, result["data"]["signIn"]["success"]
  end

  it "returns manually-configured return types" do
    mutation = Class.new(GraphQL::Schema::Mutation) do
      graphql_name "DoStuff"
      type(String)
    end

    field = GraphQL::Schema::Field.new(name: "f", owner: nil, resolver_class: mutation)
    assert_equal "String", field.type.graphql_name
    assert_equal GraphQL::Types::String, field.type
  end

  it "inherits arguments even when parent classes aren't attached to the schema" do
    parent_mutation = Class.new(GraphQL::Schema::Mutation) do
      graphql_name "ParentMutation"
      argument :thing_id, "ID"
      field :inputs, String

      def resolve(**inputs)
        { inputs: inputs.inspect }
      end
    end

    child_mutation = Class.new(parent_mutation) do
      graphql_name "ChildMutation"
      argument :thing_name, String
    end

    mutation_type = Class.new(GraphQL::Schema::Object) do
      graphql_name "Mutation"
      field :child, mutation: child_mutation
    end

    schema = Class.new(GraphQL::Schema) do
      mutation(mutation_type)
    end

    assert_equal ["thingId", "thingName"], child_mutation.arguments.keys
    assert_equal ["thingId", "thingName"], child_mutation.all_argument_definitions.map(&:graphql_name)
    assert_equal ["thingId", "thingName"], schema.mutation.fields["child"].all_argument_definitions.map(&:graphql_name)
    res = schema.execute("mutation { child(thingName: \"abc\", thingId: \"123\") { inputs } }")
    assert_equal "{:thing_id=>\"123\", :thing_name=>\"abc\"}", res["data"]["child"]["inputs"]
  end

  describe "flushing dataloader cache" do
    class MutationDataloaderCacheSchema < GraphQL::Schema
      module Database
        DATA = {}
        def self.get(id)
          value = DATA[id] ||= 0
          OpenStruct.new(id: id, value: value)
        end

        def self.increment(id)
          DATA[id] ||= 0
          DATA[id] += 1
        end

        def self.clear
          DATA.clear
        end
      end

      class CounterSource < GraphQL::Dataloader::Source
        def fetch(ids)
          ids.map { |id| Database.get(id) }
        end
      end
      class CounterType < GraphQL::Schema::Object
        def self.authorized?(obj, ctx)
          # Just force the load here, too:
          ctx.dataloader.with(CounterSource).load(obj.id)
          true
        end
        field :value, Integer
      end
      class Increment < GraphQL::Schema::Mutation
        field :counter, CounterType
        argument :counter_id, ID, loads: CounterType

        def resolve(counter:)
          Database.increment(counter.id)
          {
            counter: dataloader.with(CounterSource).load(counter.id)
          }
        end
      end

      class ReadyCounter < GraphQL::Schema::Mutation
        field :id, ID
        argument :counter_id, ID

        def ready?(counter_id:)
          # Just fill the cache:
          dataloader.with(CounterSource).load(counter_id)
          true
        end

        def resolve(counter_id:)
          { id: counter_id }
        end
      end

      class Mutation < GraphQL::Schema::Object
        field :increment, mutation: Increment
        field :ready_counter, mutation: ReadyCounter
      end

      mutation(Mutation)

      def self.object_from_id(id, ctx)
        ctx.dataloader.with(CounterSource).load(id)
      end

      def self.resolve_type(abs_type, obj, ctx)
        CounterType
      end

      use GraphQL::Dataloader
    end

    it "clears the cache after authorized and loads" do
      MutationDataloaderCacheSchema::Database.clear
      res = MutationDataloaderCacheSchema.execute("mutation { increment(counterId: \"4\") { counter { value } } }")
      assert_equal 1, res["data"]["increment"]["counter"]["value"]

      res2 = MutationDataloaderCacheSchema.execute("mutation { increment(counterId: \"4\") { counter { value } } }")
      assert_equal 2, res2["data"]["increment"]["counter"]["value"]
    end

    it "uses a fresh cache for `ready?` calls" do
      multiplex = [
        { query: "mutation { r1: readyCounter(counterId: 1) { id } }" },
        { query: "mutation { r2: readyCounter(counterId: 1) { id } }" },
        { query: "mutation { r3: readyCounter(counterId: 1) { id } }" },
      ]
      result = MutationDataloaderCacheSchema.multiplex(multiplex)
      assert_equal ["1", "1", "1"], result.map { |r| r["data"].first.last["id"] }
    end
  end
end
