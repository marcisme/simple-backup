require 'test/unit'
require 'rubygems'
require 'rush'

#
# This is an experiment, exploring alternative ways of
# testing shell scripts. We shall see...
#
class SimpleBackupTest < Test::Unit::TestCase

    # utility

    def config(key)
        File.readlines(".testbackuprc").each do |line|
            line.chomp!
            k, v = line.split("=")
            return v if k == key
        end
    end

    def init_backup_dirs
        FileUtils.rm_rf('.test')
        FileUtils.mkpath(ENV['REMOTE_ARCHIVE_DIR'])
        FileUtils.mkpath(ENV['LOCAL_ARCHIVE_DIR'])
        # the dirs have to exist before we can create these objects
        @dir_to_backup = Rush[ENV['DIR_TO_BACKUP']]
        @remote_archive_dir = Rush[ENV['REMOTE_ARCHIVE_DIR']]
        @local_archive_dir = Rush[ENV['LOCAL_ARCHIVE_DIR']]
    end

    def get_tar_contents(name)
        %x[#{ENV['TAR']} ztf #{@remote_archive_dir}/#{name}].split
    end

    def backup_filesystem
        system './simple-backup.sh -f &>/dev/null'
    end

    def sync_files
        system './simple-backup.sh -s &>/dev/null'
    end

    # acceptance tests

    def test_backup
        init_backup_dirs

        @dir_to_backup.create_file 'file_one'
        @dir_to_backup.create_file 'file_two'
        @dir_to_backup.create_file 'file_three'

        assert_equal(3, @dir_to_backup.files.size)

        backup_filesystem
        
        tar_contents = get_tar_contents '*.tar.gz'

        assert_equal(4, tar_contents.size)
        assert(tar_contents.include? 'home/')
        assert(tar_contents.include? 'home/file_one')
        assert(tar_contents.include? 'home/file_two')
        assert(tar_contents.include? 'home/file_three')
    end

    def test_partial_backup
        init_backup_dirs

        @dir_to_backup.create_file 'file_one'
        backup_filesystem
        @remote_archive_dir['backup_name-fs-*.tar.gz'].first.rename '1.tar.gz'

        @dir_to_backup.create_file 'file_two'
        backup_filesystem
        @remote_archive_dir['backup_name-fs-*.tar.gz'].first.rename '2.tar.gz'

        tar_contents = get_tar_contents '2.tar.gz'

        assert_equal(2, tar_contents.size)
        assert(tar_contents.include? 'home/')
        assert(tar_contents.include? 'home/file_two')
    end
    
    def test_backup_excludes
        init_backup_dirs

        @dir_to_backup.create_file 'file_one'
        @dir_to_backup.create_dir 'tmp'
        @dir_to_backup.create_file 'tmp/file_two'
        backup_filesystem
        
        tar_contents = get_tar_contents '*.tar.gz'

        assert_equal(2, tar_contents.size)
        assert(tar_contents.include? 'home/')
        assert(tar_contents.include? 'home/file_one')
    end

    def test_sync
        init_backup_dirs

        @remote_archive_dir.create_file 'file_one'
        @remote_archive_dir.create_file 'file_two'
        @remote_archive_dir.create_file 'file_three'

        assert_equal(3, @remote_archive_dir.files.size)

        sync_files

        assert_equal(3, @local_archive_dir.files.size)
        assert(@local_archive_dir['file_one'].exists?)
        assert(@local_archive_dir['file_two'].exists?)
        assert(@local_archive_dir['file_three'].exists?)
    end

    def test_last_backup
        init_backup_dirs

        backup_filesystem

        assert(@remote_archive_dir['last_backup'].search(/1234\.5678/))
    end

    def test_deploy
        init_backup_dirs

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

        system './simple-backup.sh -u &>/dev/null'

        assert(remote_home['.backuprc'].exists?)
        assert(remote_home['.backupexclude'].exists?)
        assert(remote_bin['simple-backup.sh'].exists?)
    end

end
