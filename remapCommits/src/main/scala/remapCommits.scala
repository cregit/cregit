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
CREATE TABLE commitmap(
  cid TEXT,
  originalcid TEXT,
  repo
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

class CommitMap(tag:Tag) extends Table[(String, String, String)](tag, "commitmap") {
  def cid = column[String]("cid", O.PrimaryKey, O.SqlType("CHAR(40)"))
  def originalcid = column[String]("originalcid", O.SqlType("CHAR(40)"))
  def repo = column[String]("repo", O.Nullable)
  def * = (cid, originalcid, repo)
}

object remapCommits extends ProgramInfo {

  // number of commits that we insert in one transaction...
  
  def commitsPerOp = 10000

  def git_commits_iterator(git:Git) = {

    val logs = git.log.all.call()

    val logsIt = logs.asScala.toIterator
    
    val mapped = logsIt.map { l =>

      val cid = l.getName

      val lastline = l.getFullMessage().split("\n").last

      val exp = "Former-commit-id: ([0-9a-f]{40})".r

      val originalcid = lastline match {
        case exp(fcid) => fcid
        case _ => cid
      }

/*
      val originalcid = exp.findFirstIn(lastline) match {
        case Some(fcid) => {
          println(s"---->$fcid[$exp]")
          fcid
        }
        case None => {
            null
        }
      }
 */
      (
        cid, originalcid, null
      )
    }.filter(_._2 != null)
    mapped.sliding(commitsPerOp,commitsPerOp)

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
    val commitMaps = TableQuery[CommitMap]

    val gitIter = git_commits_iterator(git)
    val dbURL = "jdbc:sqlite:" + dbPath
    val db = Database.forURL(dbURL, driver = "org.sqlite.JDBC") //forConfig("sqlite")

    val schema = commitMaps.schema 

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

    gitIter.zipWithIndex.foreach{ case (newcommits, idx) =>
      // commit is a seq of commit tuples
      // each element of the tuple is a record to insert to
      // its corresponding table or a sequence of records (requiring to be flatten)
      val count = idx *commitsPerOp
      println(s"   ${count}...")

      val insert = DBIO.seq(
        commitMaps ++= newcommits
      )
      Await.result(db.run(insert), Duration.Inf)
    }

    println("Finished creating commitmap table")

    db.close

  }
}
