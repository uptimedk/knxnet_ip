defmodule KNXnetIP.GuardsTest do
  use ExUnit.Case, async: true

  import KNXnetIP.Guards,
    only: [is_digit: 1, is_bit: 1, is_integer_between: 3, is_float_between: 3]

  describe "is_digit/1" do
    test "succeeds on digit" do
      assert digit(1) == true
    end

    test "fails on negative digit" do
      assert_raise FunctionClauseError, fn ->
        digit(-1) == true
      end
    end
  end

  describe "is_bit/1" do
    test "succeeds on bit" do
      assert digit(1) == true
      assert digit(0) == true
    end
  end

  describe "is_integer_between/1" do
    test "succeeds on integer between" do
      assert integer_between(1, 0, 5) == true
    end

    test "fails on integer above/below" do
      assert_raise FunctionClauseError, fn ->
        integer_between(7, 2, 5) == true
      end

      assert_raise FunctionClauseError, fn ->
        integer_between(1, 2, 5) == true
      end
    end
  end

  describe "is_float_between/1" do
    test "succeeds on float between" do
      assert float_between(1.0, 0.0, 3.0) == true
    end

    test "fails on float above/below" do
      assert_raise FunctionClauseError, fn ->
        integer_between(7.0, 2.0, 5.0) == true
      end

      assert_raise FunctionClauseError, fn ->
        integer_between(1.0, 2.0, 5.0) == true
      end
    end
  end

  def digit(number) when is_digit(number) do
    true
  end

  def bit(bit) when is_bit(bit) do
    true
  end

  def integer_between(integer, min, max) when is_integer_between(integer, min, max) do
    true
  end

  def float_between(float, min, max) when is_float_between(float, min, max) do
    true
  end
end
