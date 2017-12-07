/*

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
 
*/

import slick.driver.SQLiteDriver.api._
import scala.concurrent.{Future, Await}
import scala.concurrent.ExecutionContext.Implicits.global
import scala.concurrent.duration.Duration
import scala.util.{Failure, Success}
import scala.io.Source

import org.eclipse.jgit.api._
import org.eclipse.jgit._
import org.eclipse.jgit.treewalk.TreeWalk
import org.eclipse.jgit.lib.Config

import scala.collection.JavaConverters._

import java.io.File
import java.text.SimpleDateFormat;

// schema to create

/*
CREATE TABLE commits (
    cid character(40),
    author character varying(200),
    autdate TEXT,
    committer character varying(200),
    comdate TEXT,
    summary varchar,
    ismerge boolean,

    PRIMARY KEY(cid));
 */

/*
CREATE TABLE parents (
    cid character(40),
    idx integer,
    parent character(40),

    PRIMARY KEY(cid,idx),
    FOREIGN KEY(cid) REFERENCES commits(cid),
    FOREIGN KEY(parent) REFERENCES commits(cid)
);
*/

/*
CREATE TABLE footers (
    cid character(40),
    idx integer,
    key TEXT,
    value TEXT,

    PRIMARY KEY(cid,idx),
    FOREIGN KEY(cid) REFERENCES commits(cid),
    FOREIGN KEY(parent) REFERENCES commits(cid)
);
*/


/*
CREATE TABLE logs (
    cid character(40),
    log TEXT,

    PRIMARY KEY(cid),
    FOREIGN KEY(cid) REFERENCES commits(cid)
);
*/


trait ProgramInfo {

  val programInfo = {
    val filenames = new RuntimeException("").getStackTrace.map { t => t.getFileName }
    val scala = filenames.indexOf("NativeMethodAccessorImpl.java")

    if (scala == -1)
      "<console>"
    else
      filenames(scala - 1)
  }
}

class Parents(tag:Tag) extends Table[(String, Int, String)](tag, "parents") {
  def cid = column[String]("cid", O.SqlType("CHAR(40)"))
  def idx = column[Int]("idx")
  def parent = column[String]("parent", O.SqlType("CHAR(40)"))
  def pk = primaryKey("pk_cid_idx", (cid, idx))
  def * = (cid, idx, parent)
}

class Logs(tag:Tag) extends Table[(String, String)](tag, "logs") {
  def cid = column[String]("cid", O.PrimaryKey, O.SqlType("CHAR(40)"))
  def log = column[String]("log", O.SqlType("TEXT"))
  def * = (cid, log)
}

class Commits(tag:Tag) extends Table[(String, String, String, String, String, String, String, String, Boolean)](tag, "commits") {
  def cid = column[String]("cid", O.PrimaryKey, O.SqlType("CHAR(40)"))
  def autname  = column[String]("autname", O.SqlType("TEXT"))
  def autemail  = column[String]("autemail", O.SqlType("TEXT"))
  def autdate  = column[String]("autdate", O.SqlType("TEXT"))
  def comname  = column[String]("comname", O.SqlType("TEXT"))
  def comemail  = column[String]("comemail", O.SqlType("TEXT"))
  def comdate  = column[String]("comdate", O.SqlType("TEXT"))
  def summary = column[String]("summary", O.SqlType("TEXT"))
  def ismerge = column[Boolean]("ismerge", O.SqlType("BOOLEAN"))
  def * = (cid, autname, autemail, autdate, comname, comemail, comdate, summary, ismerge)
}

class Footers(tag:Tag) extends Table[(String, Int, String, String)](tag, "footers") {
  def cid = column[String]("cid", O.SqlType("CHAR(40)"))
  def idx = column[Int]("idx")
  def key = column[String]("key", O.SqlType("TEXT"))
  def value = column[String]("value", O.SqlType("TEXT"))
  def pk = primaryKey("pk_cid_idx", (cid, idx))
  def * = (cid, idx, key, value)
}

object gitLogToDB extends ProgramInfo {

  // number of commits that we insert in one transaction...
  
  def commitsPerOp = 10000

  def git_commits_iterator(git:Git) = {

    val logs = git.log.all.call()

    val logsIt = logs.asScala.toIterator
    
    val mapped = logsIt.map { l =>
      val dt = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
      val aWhen: String = dt.format(l.getAuthorIdent().getWhen)
      val cWhen: String = dt.format(l.getCommitterIdent().getWhen)

      val cid = l.getName

      val footers = l.getFooterLines.asScala

      val footersSeq = footers.zipWithIndex.map{f =>
        (cid, f._2, f._1.getKey, f._1.getValue)
      }.toSeq

      val parentsSeq = l.getParents.zipWithIndex.map{p =>
          (cid, p._2, p._1.getName)
        }.toSeq

      val aut = l.getAuthorIdent()
      val com = l.getCommitterIdent()

      def remove_trailing_space(st:String) = st.replaceAll(" $", "")

      (
        // first is the commit tuple
        // second is the log tuple
        // third is a sequence of parents tuple
        // fourth is a sequence of footers tuple

        (cid,
          remove_trailing_space(aut.getName), aut.getEmailAddress,
          aWhen,
          remove_trailing_space(com.getName), com.getEmailAddress,
          cWhen,
          l.getShortMessage,  l.getParentCount > 1
        ),
        (cid, l.getFullMessage()
        ),
        parentsSeq,
        footersSeq
      )
    }
    mapped.sliding(commitsPerOp,commitsPerOp)

  }

  def isBare(git:Git) : Boolean = {
    val storedConfig = git.getRepository.getConfig
    storedConfig.getBoolean("core", null, "bare", false)
  }

  def findGrafts(repo:String, git:Git) = {
    val graftsFileName = repo + (if (isBare(git)) "" else "/.git/") + "info/grafts"

    // we assume that the heads of the grafts do not have any other parent...
    // otherwise parent cannot be 1

    // but why fix now? we might never run into that case
    // we'll see

    if ((new File(graftsFileName)).exists) {
      Source.fromFile(graftsFileName).getLines.map { l =>
        val f = l.split(' ')
        (f(1), 1, f(0))
      }.toList
    } else {
      List()
    }
  }

  def main(args: Array[String]) {

  // the functionality is a bit odd

  // we use slick to insert to the database.
  /// slick requires, per transaction, a set of tuples

  // so we create an iterator over the commits

  // the iterator lazily loads one window (commitsPerOp) at a time
  // when we request it
  // 
  // so we don't run out of memory with large repos (e.g. linux)


    if (args.size != 2) {
      println(s"Usage $programInfo <db> <pathtorepo>")
      System.exit(1)
    }

    val repo = args(1)
    val dbPath = args(0)
    println(s"Processing repo... [$repo] into database [$dbPath]")

    val fileRepo = new File(repo)

    val git = Git.open(fileRepo)

    // check if it is bare
    val commits = TableQuery[Commits]
    val parents = TableQuery[Parents]
    val logs = TableQuery[Logs]
    val footers = TableQuery[Footers]

    val gitIter = git_commits_iterator(git)
    val dbURL = "jdbc:sqlite:" + dbPath
    val db = Database.forURL(dbURL, driver = "org.sqlite.JDBC") //forConfig("sqlite")

    val schema = commits.schema ++ parents.schema ++ logs.schema ++ footers.schema

    println("Creating schema...")

    try {
      Await.result(db.run(DBIO.seq(
        schema.drop
      )), Duration.Inf)
    }
    catch {
      case _: Throwable => println(Console.RED +  "Unable to drop tables " + Console.RESET )
    }

    try {
      Await.result(db.run(DBIO.seq(
        schema.create
      )), Duration.Inf)
    }
    catch {
      case _: Throwable => println(Console.RED +  "Unable to create tables " + Console.RESET )
    }

    println("Processing commits...")

    gitIter.zipWithIndex.foreach{ commitp =>
      // commit is a seq of commit tuples
      // each element of the tuple is a record to insert to
      // its corresponding table or a sequence of records (requiring to be flatten)
      val commit = commitp._1

      val insert = DBIO.seq(
        commits ++= commit.map(_._1),
        logs ++= commit.map(_._2),
        parents ++= commit.map(_._3).flatten,
        footers ++= commit.map(_._4).flatten
      )
      Await.result(db.run(insert), Duration.Inf)

      val idx = commitp._2 *commitsPerOp + commit.map(_._1).size
      println(s"   ${idx}...")

    }
    println("Done with commits")

    val grafts = findGrafts(repo, git)

    if (grafts.size > 0) {

      println("Processing grafts...")

      val insertGr = DBIO.seq(
        parents ++= grafts)

      Await.result(db.run(insertGr), Duration.Inf)
    }
    

    println("Finished creating database")

    db.close

  }
}
