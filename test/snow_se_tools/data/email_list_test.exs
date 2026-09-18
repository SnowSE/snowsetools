defmodule SnowSeTools.Data.EmailListTest do
  use ExUnit.Case, async: true

  alias SnowSeTools.Data.EmailList

  describe "parse/1" do
    test "a single plain address" do
      assert EmailList.parse("user@example.com") == ["user@example.com"]
      assert EmailList.parse("  user@example.com  ") == ["user@example.com"]
    end

    test "an Outlook list of quoted names and bracketed addresses" do
      pasted = ~s("First Last" <first.last@snow.edu>; "Other Person" <Other.Person@snow.edu>)

      assert EmailList.parse(pasted) == ["first.last@snow.edu", "other.person@snow.edu"]
    end

    test "semicolons, commas and newlines all separate entries" do
      assert EmailList.parse("a@snow.edu; b@snow.edu, c@snow.edu\nd@snow.edu") ==
               ["a@snow.edu", "b@snow.edu", "c@snow.edu", "d@snow.edu"]
    end

    test "a display name containing a comma does not split an entry" do
      assert EmailList.parse(~s("Last, First" <one@snow.edu>; Other, Person <two@snow.edu>)) ==
               ["one@snow.edu", "two@snow.edu"]
    end

    test "unbracketed names next to addresses" do
      assert EmailList.parse("First Last one@snow.edu, Other Person two@snow.edu") ==
               ["one@snow.edu", "two@snow.edu"]
    end

    test "repeats collapse, whatever their casing" do
      assert EmailList.parse("A@snow.edu; a@snow.edu; <A@SNOW.EDU>") == ["a@snow.edu"]
    end

    test "multi-part hosts survive intact" do
      assert EmailList.parse("someone@mail.example.co.uk.") == ["someone@mail.example.co.uk"]
    end

    test "nothing address-shaped yields nothing" do
      assert EmailList.parse("") == []
      assert EmailList.parse("   ") == []
      assert EmailList.parse("First Last") == []
      assert EmailList.parse("not-an-email@localhost") == []
      assert EmailList.parse(nil) == []
    end
  end
end
