/*
 *    Copyright (C) 2013 Venom authors and contributors
 *
 *    This file is part of Venom.
 *
 *    Venom is free software: you can redistribute it and/or modify
 *    it under the terms of the GNU General Public License as published by
 *    the Free Software Foundation, either version 3 of the License, or
 *    (at your option) any later version.
 *
 *    Venom is distributed in the hope that it will be useful,
 *    but WITHOUT ANY WARRANTY; without even the implied warranty of
 *    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *    GNU General Public License for more details.
 *
 *    You should have received a copy of the GNU General Public License
 *    along with Venom.  If not, see <http://www.gnu.org/licenses/>.
 */

namespace Venom {

  public interface IHistoryStorage : GLib.Object {
    public abstract void on_message(Contact c, string message, bool issender);
    public abstract GLib.List<Message>? retrieve_history(Contact c);
    public abstract void delete_history(Contact c);
    public abstract void connect_to(ToxSession session);
    public abstract void disconnect_from(ToxSession session);
  }

  public interface IAliasStorage : GLib.Object {
    public abstract string get_alias(Contact c);
    public abstract int set_alias(Contact c, string newAlias);
    public abstract void set_session(ToxSession session);
  }

  public class DummyStorage : IHistoryStorage, GLib.Object {
    public void on_message(Contact c, string message, bool issender) {}
    public GLib.List<Message>? retrieve_history(Contact c) { return null; }
    public void delete_history(Contact c) {}
    public void connect_to(ToxSession session) {}
    public void disconnect_from(ToxSession session) {}
  }

  public class SQLiteStorage : IHistoryStorage, IAliasStorage, GLib.Object {
    private unowned ToxSession session;

    private Sqlite.Database db;

    private Sqlite.Statement insert_message_statement;

    private Sqlite.Statement select_message_statement;

    private Sqlite.Statement insert_alias_statement;

    private Sqlite.Statement select_alias_statement;

    private Sqlite.Statement update_alias_statement;

    public SQLiteStorage() {
      init_db(false);
    }

    public void set_session(ToxSession session) {
      this.session = session;
    }

    public void connect_to(ToxSession session) {
      this.session = session;
      init_db(true);
      session.on_own_message.connect(on_outgoing_message);
      session.on_friend_message.connect(on_incoming_message);
    }

    public void disconnect_from(ToxSession session) {
      session.on_own_message.disconnect(on_outgoing_message);
      session.on_friend_message.disconnect(on_incoming_message);
    }

    private void on_incoming_message(Contact c, string message) {
      on_message(c, message, false);
    }

    private void on_outgoing_message(Contact c, string message) {
      on_message(c, message, true);
    }

    public void on_message(Contact c, string message, bool issender) {

      int param_position = insert_message_statement.bind_parameter_index ("$USER");
      assert (param_position > 0);
      string myId = Tools.bin_to_hexstring(session.get_address());
      insert_message_statement.bind_text(param_position, myId);

      param_position = insert_message_statement.bind_parameter_index ("$CONTACT");
      assert (param_position > 0);
      string cId = Tools.bin_to_hexstring(c.public_key);
      insert_message_statement.bind_text(param_position, cId);

      param_position = insert_message_statement.bind_parameter_index ("$MESSAGE");
      assert (param_position > 0);
      insert_message_statement.bind_text(param_position, message);

      param_position = insert_message_statement.bind_parameter_index ("$TIME");
      assert (param_position > 0);
      DateTime nowTime = new DateTime.now_utc();
      insert_message_statement.bind_int64(param_position, nowTime.to_unix());

      param_position = insert_message_statement.bind_parameter_index ("$SENDER");
      assert (param_position > 0);
      insert_message_statement.bind_int(param_position, issender?1:0);

      insert_message_statement.step ();
      

      insert_message_statement.reset ();
    }

    public GLib.List<Message>? retrieve_history(Contact c) {
      int param_position = select_message_statement.bind_parameter_index ("$USER");
      assert (param_position > 0);
      string myId = Tools.bin_to_hexstring(session.get_address());
      select_message_statement.bind_text(param_position, myId);

      param_position = select_message_statement.bind_parameter_index ("$CONTACT");
      assert (param_position > 0);
      string cId = Tools.bin_to_hexstring(c.public_key);
      select_message_statement.bind_text(param_position, cId);

      param_position = select_message_statement.bind_parameter_index ("$OLDEST");
      assert (param_position > 0);
      DateTime earliestTime = new DateTime.now_utc();
      earliestTime = earliestTime.add_days (-VenomSettings.instance.days_to_log);
      select_message_statement.bind_int64(param_position, earliestTime.to_unix());

      List<Message> messages = new List<Message>();

      while (select_message_statement.step () == Sqlite.ROW) {
        string message = select_message_statement.column_text(3);
        int64 timestamp = select_message_statement.column_int64(4);
        bool issender = select_message_statement.column_int(5) != 0;
        DateTime send_time = new DateTime.from_unix_utc (timestamp);
        Message mess;
        if(issender) {
          mess = new Message.outgoing(c, message, send_time);
        } else {
          mess = new Message.incoming(c, message, send_time);
        }
        messages.append(mess);
      }

      select_message_statement.reset ();
      return messages;
    }

    public void delete_history(Contact c) {
      //TODO
    }

    public string get_alias(Contact c) {

      int param_position = select_alias_statement.bind_parameter_index ("$USER");
      assert (param_position > 0);
      string myId = Tools.bin_to_hexstring(session.get_address());
      select_alias_statement.bind_text(param_position, myId);

      param_position = select_alias_statement.bind_parameter_index ("$CONTACT");
      assert (param_position > 0);
      string cId = Tools.bin_to_hexstring(c.public_key);
      select_alias_statement.bind_text(param_position, cId);

      string alias = null;

      while (select_alias_statement.step () == Sqlite.ROW) {
        alias = select_alias_statement.column_text(0);
      }

      select_alias_statement.reset();

      return alias;
    }

    //will return code depending on operation and sucess
    public int set_alias(Contact c, string newAlias) {
      if (get_alias(c) != null) {
        return update_alias(c, newAlias);
      } else {
        return create_alias(c, newAlias);
      }
    }

    private int update_alias(Contact c, string newAlias) {
      int param_position = update_alias_statement.bind_parameter_index ("$USER");
      assert (param_position > 0);
      string myId = Tools.bin_to_hexstring(session.get_address());
      update_alias_statement.bind_text(param_position, myId);

      param_position = update_alias_statement.bind_parameter_index ("$CONTACT");
      assert (param_position > 0);
      string cId = Tools.bin_to_hexstring(c.public_key);
      update_alias_statement.bind_text(param_position, cId);

      param_position = update_alias_statement.bind_parameter_index ("$ALIAS");
      assert (param_position > 0);
      update_alias_statement.bind_text(param_position, newAlias);

      while (update_alias_statement.step () == Sqlite.ROW) {}

      update_alias_statement.reset();

      return 0;
    }

    private int create_alias(Contact c,string newAlias) {
      int param_position = insert_alias_statement.bind_parameter_index ("$USER");
      assert (param_position > 0);
      string myId = Tools.bin_to_hexstring(session.get_address());
      insert_alias_statement.bind_text(param_position, myId);

      param_position = insert_alias_statement.bind_parameter_index ("$CONTACT");
      assert (param_position > 0);
      string cId = Tools.bin_to_hexstring(c.public_key);
      insert_alias_statement.bind_text(param_position, cId);

      param_position = insert_alias_statement.bind_parameter_index ("$ALIAS");
      assert (param_position > 0);
      insert_alias_statement.bind_text(param_position, newAlias);

      while (insert_alias_statement.step () == Sqlite.ROW) {}

      insert_alias_statement.reset();

      return 0;
    }

    private int init_db(bool with_logging) {

      // Open/Create a database:
      string filepath = ResourceFactory.instance.db_filename;
      int ec = Sqlite.Database.open (filepath, out db);
      if (ec != Sqlite.OK) {
        stderr.printf ("Can't open database: %d: %s\n", db.errcode (), db.errmsg ());
        return -1;
      }

      int ret_value = 0;

      if (with_logging) {
        ret_value = setup_logging();
        if (ret_value != 0)
          return ret_value;
      }

      ret_value = setup_aliases();
      if (ret_value != 0)
        return ret_value;

      stdout.printf ("Created db.\n");

      return 0;
    }

    private int setup_logging() {

      string errmsg;
      int ec;


      //create table and index if needed
      const string query = """
      CREATE TABLE IF NOT EXISTS History (
        id  INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        userHash  TEXT  NOT NULL,
        contactHash TEXT  NOT NULL,
        message TEXT  NOT NULL,
        timestamp INTEGER NOT NULL,
        issent INTEGER NOT NULL
      );
      """;

      ec = db.exec (query, null, out errmsg);
      if (ec != Sqlite.OK) {
        stderr.printf ("Error: %s\n", errmsg);
        return -1;
      }

      const string index_query = """
        CREATE UNIQUE INDEX IF NOT EXISTS main_index ON History (userHash, contactHash, timestamp);
      """;

      ec = db.exec (index_query, null, out errmsg);
      if (ec != Sqlite.OK) {
        stderr.printf ("Error: %s\n", errmsg);
        return -1;
      }

      //prepare insert statement for adding new history messages
      const string prepared_insert_str = "INSERT INTO History (userHash, contactHash, message, timestamp, issent) VALUES ($USER, $CONTACT, $MESSAGE, $TIME, $SENDER);";
      ec = db.prepare_v2 (prepared_insert_str, prepared_insert_str.length, out insert_message_statement);
      if (ec != Sqlite.OK) {
        stderr.printf ("Error: %d: %s\n", db.errcode (), db.errmsg ());
        return -1;
      }

      //prepare select statement to get history. Will execute on indexed data
      const string prepared_select_str = "SELECT * FROM History WHERE userHash = $USER AND contactHash = $CONTACT AND timestamp > $OLDEST;";
      ec = db.prepare_v2 (prepared_select_str, prepared_select_str.length, out select_message_statement);
      if (ec != Sqlite.OK) {
        stderr.printf ("Error: %d: %s\n", db.errcode (), db.errmsg ());
        return -1;
      }

      return 0;
    }

    private int setup_aliases() {

      string errmsg;
      int ec;

      const string query = """
      CREATE TABLE IF NOT EXISTS Aliases (
        userHash TEXT NOT NULL,
        contactHash TEXT NOT NULL,
        alias TEXT NOT NULL,
        PRIMARY KEY (userHash, contactHash)
      );
      """;

      ec = db.exec (query, null, out errmsg);
      if (ec != Sqlite.OK) {
        stderr.printf ("Error: %s\n", errmsg);
        return -1;
      }

      const string index_query = """
        CREATE UNIQUE INDEX IF NOT EXISTS main_index ON Aliases (userHash, contactHash);
      """;

      ec = db.exec (index_query, null, out errmsg);
      if (ec != Sqlite.OK) {
        stderr.printf ("Error: %s\n", errmsg);
        return -1;
      }

      const string prepared_insert_str = "INSERT INTO Aliases (userHash, contactHash, alias) VALUES ($USER, $CONTACT, $ALIAS);";
      ec = db.prepare_v2 (prepared_insert_str, prepared_insert_str.length, out insert_alias_statement);
      if (ec != Sqlite.OK) {
        stderr.printf ("Error: %d: %s\n", db.errcode (), db.errmsg ());
        return -1;
      }

      //Update statement to edit alias. Will execute on indexed data
      const string prepared_update_str = "UPDATE Aliases SET alias='$ALIAS' WHERE userHash = $USER AND contactHash = $CONTACT;";
      ec = db.prepare_v2 (prepared_update_str, prepared_update_str.length, out update_alias_statement);
      if (ec != Sqlite.OK) {
        stderr.printf ("Error: %d: %s\n", db.errcode (), db.errmsg ());
        return -1;
      }

      //prepare select statement to get aliases. Will execute on indexed data
      const string prepared_select_str = "SELECT alias FROM Aliases WHERE userHash = $USER AND contactHash = $CONTACT;";
      ec = db.prepare_v2 (prepared_select_str, prepared_select_str.length, out select_alias_statement);
      if (ec != Sqlite.OK) {
        stderr.printf ("Error: %d: %s\n", db.errcode (), db.errmsg ());
        return -1;
      }

      return 0;
    }

  }
}