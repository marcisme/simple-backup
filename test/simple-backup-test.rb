require 'test/unit'
require 'rubygems'
require 'rush'

#
# This is an experiment, exploring alternative ways of
# testing shell scripts. We shall see...
#
class SimpleBackupTest < Test::Unit::TestCase

    SIMPLE_BACKUP='../simple-backup.sh'

    # utility

    Rush::File.class_eval do

        def ztf
            %x[#{ENV['TAR']} ztf #{self.full_path}].split
        end

    end

    def setup
        FileUtils.rm_rf('.test')
        FileUtils.mkpath(ENV['REMOTE_ARCHIVE_DIR'])
        FileUtils.mkpath(ENV['LOCAL_ARCHIVE_DIR'])
        # the dirs have to exist before we can create these objects
        @dir_to_backup = Rush[ENV['DIR_TO_BACKUP']]
        @remote_archive_dir = Rush[ENV['REMOTE_ARCHIVE_DIR']]
        @local_archive_dir = Rush[ENV['LOCAL_ARCHIVE_DIR']]
    end

    # acceptance tests

    def test_backup
        @dir_to_backup.create_file 'file_one'
        @dir_to_backup.create_file 'file_two'
        @dir_to_backup.create_file 'file_three'

        assert_equal(3, @dir_to_backup.files.size)

        system "#{SIMPLE_BACKUP} -f &>/dev/null"
        
        tar_contents = @remote_archive_dir[ENV['FS_ARCHIVE_FILE_NAME']].ztf

        assert_equal(4, tar_contents.size)
        assert(tar_contents.include?('home/'))
        assert(tar_contents.include?('home/file_one'))
        assert(tar_contents.include?('home/file_two'))
        assert(tar_contents.include?('home/file_three'))
    end

    def test_partial_backup
        @dir_to_backup.create_file 'file_one'
        system "#{SIMPLE_BACKUP} -f &>/dev/null"
        @remote_archive_dir[ENV['FS_ARCHIVE_FILE_NAME']].rename '1.tar.gz'

        @dir_to_backup.create_file 'file_two'
        system "#{SIMPLE_BACKUP} -f &>/dev/null"
        @remote_archive_dir[ENV['FS_ARCHIVE_FILE_NAME']].rename '2.tar.gz'

        tar_contents = @remote_archive_dir['2.tar.gz'].ztf

        assert_equal(2, tar_contents.size)
        assert(tar_contents.include?('home/'))
        assert(tar_contents.include?('home/file_two'))
    end
    
    def test_force_full_backup
        @dir_to_backup.create_file 'file_one'
        system "#{SIMPLE_BACKUP} -f &>/dev/null"
        @remote_archive_dir[ENV['FS_ARCHIVE_FILE_NAME']].rename '1.tar.gz'

        @dir_to_backup.create_file 'file_two'
        system "#{SIMPLE_BACKUP} -fo &>/dev/null"
        @remote_archive_dir[ENV['FS_ARCHIVE_FILE_NAME']].rename '2.tar.gz'

        tar_contents = @remote_archive_dir['2.tar.gz'].ztf

        assert_equal(3, tar_contents.size)
        assert(tar_contents.include?('home/'))
        assert(tar_contents.include?('home/file_one'))
        assert(tar_contents.include?('home/file_two'))
    end
    
    def test_backup_excludes
        @dir_to_backup.create_file 'file_one'
        @dir_to_backup.create_dir 'tmp'
        @dir_to_backup.create_file 'tmp/file_two'
        system "#{SIMPLE_BACKUP} -f &>/dev/null"
        
        tar_contents = @remote_archive_dir[ENV['FS_ARCHIVE_FILE_NAME']].ztf

        assert_equal(2, tar_contents.size)
        assert(tar_contents.include?('home/'))
        assert(tar_contents.include?('home/file_one'))
    end

    def test_sync
        @remote_archive_dir.create_file 'file_one'
        @remote_archive_dir.create_file 'file_two'
        @remote_archive_dir.create_file 'file_three'

        assert_equal(3, @remote_archive_dir.files.size)

        system "#{SIMPLE_BACKUP} -s &>/dev/null"

        assert_equal(3, @local_archive_dir.files.size)
        assert(@local_archive_dir['file_one'].exists?)
        assert(@local_archive_dir['file_two'].exists?)
        assert(@local_archive_dir['file_three'].exists?)
    end

    def test_last_backup
        system "#{SIMPLE_BACKUP} -f &>/dev/null"

        assert(@remote_archive_dir['last_backup'].search(/20100101\.000000/))
    end

    def test_deploy
        remote_home = Rush[ENV['REMOTE_HOME']]
        remote_home.create_dir('bin')
        remote_bin = remote_home['bin']
        local_home = Rush[ENV['LOCAL_HOME']]
        local_home.create_dir('bin')
        local_bin = local_home['bin']

        local_home.create_file '.backuprc'
        local_home.create_file '.backupexclude'
        local_bin.create_file 'simple-backup.sh'

        assert(!remote_home['.backuprc'].exists?)
        assert(!remote_home['.backupexclude'].exists?)
        assert(!remote_bin['simple-backup.sh'].exists?)

        system "#{SIMPLE_BACKUP} -u &>/dev/null"

        assert(remote_home['.backuprc'].exists?)
        assert(remote_home['.backupexclude'].exists?)
        assert(remote_bin['simple-backup.sh'].exists?)
    end

    def test_no_notification
        @local_archive_dir['last_backup'] << ENV['TIMESTAMP']

        rc = system "#{SIMPLE_BACKUP} -n &>/dev/null"

        assert(rc)
    end

    # This test will result in a growlnotify notification
    def test_notification
        @local_archive_dir['last_backup'] << "19781220.000000"

        rc = system "#{SIMPLE_BACKUP} -n &>/dev/null"

        assert(!rc)
    end

end
