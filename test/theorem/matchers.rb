module Tests
  class MatchersTest < Base
    let(:tests) do
      Class.new do
        include Fixture
        include Matchers

        test "errors - eql" do
          expect("foo").to eql("bar")
        end

        test "errors - include" do
          expect(%w[one two three]).to include(%w[one four])
        end

        test "errors - be" do
          expect(true).to be(false)
        end
      end
    end

    test "errors" do
      res = tests.run!
      expect(res[0].error.message).to eql('"foo" does not equal "bar"')
      expect(res[1].error.message).to eql('["one", "two", "three"] does not include ["one", "four"]')
      expect(res[2].error.message).to match(/TrueClass\.object_id\(\d+\) does not equal FalseClass\.object_id\(\d+\)/)
    end
  end
end
