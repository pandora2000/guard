require "guard/cli"

# TODO: instead of shared examples, use have_received if possible
RSpec.shared_examples "avoids Bundler warning" do |meth|
  it "does not show the Bundler warning" do
    expect(Guard::UI).to_not receive(:info).with(/Guard here!/)
    subject.send(meth)
  end
end

RSpec.shared_examples "shows Bundler warning" do |meth|
  it "shows the Bundler warning" do
    expect(Guard::UI).to receive(:info).with(/Guard here!/)
    subject.send(meth)
  end
end

RSpec.shared_examples "gem dependency warning" do |meth|
  let(:guard_options) { double("hash_with_options") }
  let(:gemdeps) { nil }
  let(:gemfile) { nil }

  before do
    allow(ENV).to receive(:[]).with("BUNDLE_GEMFILE").and_return(gemfile)
    allow(ENV).to receive(:[]).with("RUBYGEMS_GEMDEPS").and_return(gemdeps)
  end

  context "without an existing Gemfile" do
    before { expect(File).to receive(:exist?).with("Gemfile") { false } }
    include_examples "avoids Bundler warning", meth
  end

  context "with an existing Gemfile" do
    before { allow(File).to receive(:exist?).with("Gemfile") { true } }

    context "with Bundler" do
      let(:gemdeps) { nil }
      let(:gemfile) { "Gemfile" }
      include_examples "avoids Bundler warning", meth
    end

    context "without Bundler" do
      let(:gemfile) { nil }

      context "with Rubygems Gemfile autodetection or custom Gemfile" do
        let(:gemdeps) { "-" }
        include_examples "avoids Bundler warning", meth
      end

      context "without Rubygems Gemfile handling" do
        let(:gemdeps) { nil }

        context "with :no_bundler_warning option" do
          before { @options[:no_bundler_warning] = true }
          include_examples "avoids Bundler warning", meth
        end

        context "without :no_bundler_warning option" do
          include_examples "shows Bundler warning", meth
        end
      end
    end
  end
end

RSpec.describe Guard::CLI do
  let(:guard)         { Guard }
  let(:ui)            { Guard::UI }

  let(:dsl_describer) { instance_double("Guard::DslDescriber") }
  let(:evaluator) { instance_double("Guard::Guardfile::Evaluator") }
  let(:generator) { instance_double("Guard::Guardfile::Generator") }
  let(:obsolete_guardfile) { class_double("Guard::Guardfile") }

  let(:session) { instance_double("Guard::Internals::Session") }
  let(:state) { instance_double("Guard::Internals::State") }

  before do
    @options = {}
    allow(subject).to receive(:options).and_return(@options)

    allow(Guard::Guardfile::Evaluator).to receive(:new).and_return(evaluator)
    allow(Guard::Guardfile::Generator).to receive(:new).and_return(generator)

    allow(::Guard::DslDescriber).to receive(:new).with(no_args).
      and_return(dsl_describer)
  end

  describe "#start" do
    include_examples "gem dependency warning", :start

    before do
      allow(File).to receive(:exist?).with("Gemfile").and_return(false)
      allow(Guard).to receive(:start)
    end

    it "delegates to Guard.start" do
      expect(Guard).to receive(:start)

      subject.start
    end
  end

  describe "#list" do
    before do
      allow(evaluator).to receive(:evaluate)
      allow(session).to receive(:evaluator_options)
      allow(state).to receive(:session).and_return(session)
      allow(Guard::Internals::State).to receive(:new).and_return(state)
    end

    it "outputs the Guard plugins list" do
      expect(dsl_describer).to receive(:list)
      subject.list
    end
  end

  describe "#notifiers" do
    before do
      # TODO: refactor this out (here and above)
      allow(evaluator).to receive(:evaluate)
      allow(session).to receive(:evaluator_options)
      allow(state).to receive(:session).and_return(session)
      allow(Guard::Internals::State).to receive(:new).and_return(state)
    end

    it "outputs the notifiers list" do
      expect(dsl_describer).to receive(:notifiers)
      subject.notifiers
    end
  end

  describe "#version" do
    it "shows the current version" do
      expect(STDOUT).to receive(:puts).with(/#{ ::Guard::VERSION }/)
      subject.version
    end
  end

  describe "#init" do
    include_examples "gem dependency warning", :init

    before do
      stub_file("Gemfile")

      allow(evaluator).to receive(:evaluate)
      allow(generator).to receive(:create_guardfile)
      allow(generator).to receive(:initialize_all_templates)

      allow(session).to receive(:evaluator_options)
      allow(state).to receive(:session).and_return(session)
      allow(Guard::Internals::State).to receive(:new).and_return(state)
    end

    context "with bare option" do
      before { @options[:bare] = true }

      it "Only creates the Guardfile without initializing any Guard template" do
        allow(evaluator).to receive(:evaluate).
          and_raise(Guard::Guardfile::Evaluator::NoGuardfileError)

        allow(File).to receive(:exist?).with("Gemfile").and_return(false)
        expect(generator).to receive(:create_guardfile)
        expect(generator).to_not receive(:initialize_template)
        expect(generator).to_not receive(:initialize_all_templates)

        subject.init
      end
    end

    # TODO: this is a code smell suggesting the use of global variables
    # instead of object oriented programming
    context "with no bare option" do
      before { @options[:bare] = false }

      it "evaluates created or existing guardfile" do
        expect(evaluator).to receive(:evaluate)
        subject.init
      end

      it "creates a Guardfile" do
        expect(evaluator).to receive(:evaluate).
          and_raise(Guard::Guardfile::Evaluator::NoGuardfileError).once
        expect(evaluator).to receive(:evaluate)

        expect(Guard::Guardfile::Generator).to receive(:new).
          and_return(generator)
        expect(generator).to receive(:create_guardfile)

        subject.init
      end

      it "initializes templates of all installed Guards" do
        allow(File).to receive(:exist?).with("Gemfile").and_return(false)

        expect(generator).to receive(:initialize_all_templates)

        subject.init
      end

      it "initializes each passed template" do
        allow(File).to receive(:exist?).with("Gemfile").and_return(false)

        expect(generator).to receive(:initialize_template).with("rspec")
        expect(generator).to receive(:initialize_template).with("pow")

        subject.init "rspec", "pow"
      end

      context "when passed a guard name" do
        it "initializes the template of the passed Guard" do
          expect(generator).to receive(:initialize_template).with("rspec")

          subject.init "rspec"
        end
      end
    end
  end

  describe "#show" do
    before do
      # TODO: refactor this out (here and above)
      allow(session).to receive(:evaluator_options)
      allow(state).to receive(:session).and_return(session)
      allow(Guard::Internals::State).to receive(:new).and_return(state)
    end

    it "outputs the Guard::DslDescriber.list result" do
      evaluator = instance_double("Guard::Guardfile::Evaluator")
      allow(evaluator).to receive(:evaluate)
      allow(Guard::Guardfile::Evaluator).to receive(:new).and_return(evaluator)

      expect(Guard::DslDescriber).to receive(:new).with(no_args).
        and_return(dsl_describer)

      expect(dsl_describer).to receive(:show)
      subject.show
    end
  end
end
