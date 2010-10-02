require 'test/unit'
require 'rubygems'
require 'rush'

#
# This is an experiment, exploring alternative ways of
# testing shell scripts. We shall see...
#
class SimpleBackupEnvTest < Test::Unit::TestCase

    # utility

    def config(key)
        File.readlines(".testbackuprc").each do |line|
            line.chomp!
            k, v = line.split("=")
            return v if k == key
        end
    end

    # These tests just make sure that the test backuprc file has
    # what we expect in it, and that the corresponding ENV vars
    # are also correct.

    def test_tar_from_backuprc
        assert_equal('gnutar', config('TAR'))
    end

    def test_backup_name_from_backuprc
        assert_equal('backup_name', config('BACKUP_NAME'))
    end

    def test_mysql_user_from_backuprc
        assert_equal('mysql_user', config('MYSQL_USER'))
    end

    def test_mysql_password_from_backuprc
        assert_equal('mysql_password', config('MYSQL_PASSWORD'))
    end

    def test_remote_user_from_backuprc
        assert_equal('marc', config('REMOTE_USER'))
    end

    def test_remote_host_from_backuprc
        assert_equal('localhost', config('REMOTE_HOST'))
    end

    def test_dir_to_backup_from_backuprc
        assert_equal('$(pwd)/.test/remote/home', config('DIR_TO_BACKUP'))
    end

    def test_remote_archive_dir_from_backuprc
        assert_equal('$(pwd)/.test/remote/home/backup', config('REMOTE_ARCHIVE_DIR'))
    end

    def test_local_archive_dir_from_backuprc
        assert_equal('$(pwd)/.test/local/home/backup', config('LOCAL_ARCHIVE_DIR'))
    end

    def test_timestamp_from_backuprc
        assert_equal('1234.5678', config('TIMESTAMP'))
    end

    def test_tar_from_env
        assert_equal('gnutar', ENV['TAR'])
    end

    def test_backup_name_from_env
        assert_equal('backup_name', ENV['BACKUP_NAME'])
    end

    def test_mysql_user_from_env
        assert_equal('mysql_user', ENV['MYSQL_USER'])
    end

    def test_mysql_password_from_env
        assert_equal('mysql_password', ENV['MYSQL_PASSWORD'])
    end

    def test_remote_user_from_env
        assert_equal('marc', ENV['REMOTE_USER'])
    end

    def test_remote_host_from_env
        assert_equal('localhost', ENV['REMOTE_HOST'])
    end

    def test_dir_to_backup_from_env
        assert_equal(Dir.pwd+'/.test/remote/home', ENV['DIR_TO_BACKUP'])
    end

    def test_remote_archive_dir_from_env
        assert_equal(Dir.pwd+'/.test/remote/home/backup', ENV['REMOTE_ARCHIVE_DIR'])
    end

    def test_local_archive_dir_from_env
        assert_equal(Dir.pwd+'/.test/local/home/backup', ENV['LOCAL_ARCHIVE_DIR'])
    end

    def test_timestamp_from_env
        assert_equal('1234.5678', ENV['TIMESTAMP'])
    end

    def test_full_day_of_week
        assert_equal(5, ENV['FULL_DAY_OF_WEEK'].to_i)
    end

    def test_local_retention_days
        assert_equal(30, ENV['LOCAL_RETENTION_DAYS'].to_i)
    end

    def test_remote_retention_days
        assert_equal(30, ENV['REMOTE_RETENTION_DAYS'].to_i)
    end

    def test_exclude_file_from_env
        assert_equal('.testbackupexclude', ENV['EXCLUDE_FILE'])
    end

    def test_exclude_file_contents
        exclude_file = Rush.dir(__FILE__)[ENV['EXCLUDE_FILE']]
        assert(exclude_file.lines.include? 'tmp')
    end

    def test_last_backup_file
        assert_equal(Dir.pwd+'/.test/remote/home/backup/last_backup', ENV['LAST_BACKUP_FILE'])
    end

end
