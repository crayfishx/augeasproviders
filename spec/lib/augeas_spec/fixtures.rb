require 'augeas'
require 'tempfile'

module AugeasSpec::Fixtures
  # Creates a temp file from a given fixture name
  # Doesn't explicitly clean up the temp file as we can't evaluate a block with
  # "let" or pass the path back via an "around" hook.
  def aug_fixture(name)
    tmp = Tempfile.new("target")
    tmp.write(File.read(my_fixture(name)))
    tmp.close
    return tmp
  end

  # Runs a particular resource via a catalog
  def apply(resource)
    catalog = Puppet::Resource::Catalog.new
    catalog.add_resource resource
    catalog.apply
  end

  # Runs a resource and checks for warnings and errors
  def apply!(resource)
    txn = apply(resource)

    # Check for warning+ log messages
    loglevels = Puppet::Util::Log.levels[3, 999]
    @logs.select { |log| loglevels.include? log.level }.should == []

    # Check for transaction success after, as it's less informative
    txn.any_failed?.should_not be_true

    # Run the exact same resource, but this time ensure there were absolutely
    # no changes (as seen by logs) to indicate if it was idempotent or not
    @logs.clear
    txn_idempotent = apply(resource)
    loglevels = Puppet::Util::Log.levels[2, 999]
    @logs.select { |log| loglevels.include? log.level }.should == []
    txn_idempotent.any_failed?.should_not be_true

    txn
  end

  # Open Augeas on a given file.  Used for testing the results of running
  # Puppet providers.
  def aug_open(file, lens, &block)
    aug = Augeas.open(nil, AugeasProviders::Provider.loadpath, Augeas::NO_MODL_AUTOLOAD)
    begin
      aug.transform(
        :lens => lens,
        :name => lens.split(".")[0],
        :incl => file
      )
      aug.set("/augeas/context", "/files#{file}")
      aug.load!
      raise AugeasSpec::Error, "Augeas didn't load #{file}" if aug.match(".").empty?
      yield aug
    rescue Augeas::Error
      errors = []
      aug.match("/augeas//error").each do |errnode|
        aug.match("#{errnode}/*").each do |subnode|
          subvalue = aug.get(subnode)
          errors << "#{subnode} = #{subvalue}"
        end
      end
      raise AugeasSpec::Error, errors.join("\n")
    ensure
      aug.close
    end
  end
end