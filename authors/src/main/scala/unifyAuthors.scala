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


import scala.collection.immutable.ListMap
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
import scalaz._
import java.text.Normalizer

import info.folone.scala.poi._
import impure._

import slick.driver.SQLiteDriver.api._
import java.io.File
import java.util.Calendar 


object  unifyAuthors {

  /*

CREATE TABLE authors(
    recordid int, 
    author text, 
    personid text, 
    email text, 
    name text, 
    lcemail text, 
    userid text, 
    domain tex, 
    autcount int,
    comcount int,
    dateadded text, 
    checked text, 
    notes text);
   */


  class Authors(tag:Tag) extends Table[(Int,
      String, String, String, String, String, String, String,
      Int, Int,
      String, Boolean, String)](tag, "authors") {
    def recordid = column[Int]("recordid", O.PrimaryKey)

    def personid = column[String]("personid",  O.SqlType("TEXT"))
    def author  = column[String]("author", O.SqlType("TEXT"))
    def email = column[String]("email",  O.SqlType("TEXT"))
    def name = column[String]("name",  O.SqlType("TEXT"))
    def lcemail = column[String]("lcemail",  O.SqlType("TEXT"))
    def userid = column[String]("userid",  O.SqlType("TEXT"))
    def domain = column[String]("domain",  O.SqlType("TEXT"))

    def autcount = column[Int]("autcount")
    def comcount = column[Int]("comcount")
    def dateadded = column[String]("dateadded",  O.SqlType("TEXT"))
    def checked = column[Boolean]("checked", O.SqlType("BOOLEAN"))
    def notes = column[String]("notes",  O.Nullable, O.SqlType("TEXT"))

    def * = (recordid, personid, author, email, name,
      lcemail, userid, domain, autcount, comcount,
      dateadded, checked, notes)
  }

  def write_database(
    dbPath:String,
    records: Map[String, List[Person]],
/*
    keyStats: Map[String, Person_key],
    allCounts: Map[Person, Int],
 */
    authorCounts: Map[Person, Int],
    commCounts: Map[Person, Int]):Unit = {

    val authors = TableQuery[Authors]

    val dbURL = "jdbc:sqlite:" + dbPath
    val db = Database.forURL(dbURL, driver = "org.sqlite.JDBC") //forConfig("sqlite")

    val schema = authors.schema

    println("Recreating schema...")

    try {
      Await.result(db.run(DBIO.seq(
        schema.drop
      )), Duration.Inf)
    }
    catch {
      case _: Throwable => {
        println(Console.RED +  "Unable to drop table " + Console.RESET )
        return
      }
        
    }

    val now = Calendar.getInstance().getTime()

    val today = (new SimpleDateFormat("yyyy-mm-dd hh:mm:ss")).format(now)


    def personRecordToTuple(idx : Int, key:String, p:Person) = {
      (idx, key, p.name + " <" + p.email + ">", p.email, p.name,
        p.lcEmail, p.lcUserId, p.lcDomain,
        authorCounts.getOrElse(p,0),
        commCounts.getOrElse(p,0),
//        "lcemail", "userid", "domain", 0, 0,
        today, false, null)
    }

    val newAuthors = records.toSeq.sortBy{_._1}.
      foldLeft((Seq[(Int, String, String, String, String,
                     String, String, String, 
                     Int, Int, String, Boolean, String)](), 0)){ case((acc, offset), (key,person)) =>
      val newRows = person.zipWithIndex.map{case (p,i) =>
        personRecordToTuple(i+offset, key, p)
      }
      (acc ++ newRows, offset + newRows.size)
    }._1

    try {
      Await.result(db.run(DBIO.seq(
        schema.create
      )), Duration.Inf)
    }
    catch {
      case _: Throwable => {
        println(Console.RED +  "Unable to create table " + Console.RESET )
        return;
      }
    }

    val insert = DBIO.seq(
        authors ++= newAuthors
    )
    Await.result(db.run(insert), Duration.Inf)

    println("Finished creating table authors...")

    db.close
  }

  def strip_accents(s:String) :String = {
    val s2 = Normalizer.normalize(s, Normalizer.Form.NFD);
    val s3 = s2.replaceAll("[\\p{InCombiningDiacriticalMarks}]", "");
  
    s3.replaceAll("ø", "o").replaceAll("ß", "ss").replaceAll("æ", "ae").replaceAll("ð", "o")
  }

  class Person(val name: String, val key: String, val email:String,
    val lcEmail:String, val lcUserId:String, val lcDomain:String) {

    val ourHashCode:Int = s"$name ($key), $email ($lcEmail,$lcUserId,$lcDomain)".hashCode

    override def toString= {
      s"Person: $name ($key), $email ($lcEmail,$lcUserId,$lcDomain)"
    }
    def canEqual(a: Any) = a.isInstanceOf[Person]

    override def equals(that: Any): Boolean =
      that match {
        case that: Person => that.canEqual(this) && this.hashCode == that.hashCode
        case _ => false
      }
    override def hashCode:Int = {
      ourHashCode
    }

  };

  class Person_key(val key:String, val preferred:String, val identCount:Int,
    val allCount:Int, val authoredCount:Int, val committedCount:Int) {
    override def toString= {
      s"Key: $key ($preferred), identities: $identCount ($allCount, $authoredCount, $committedCount))"
    }
  }

  // return an iterator that returns, for each commit
  // a tuple of the author  and the committer info
  def git_commits_iterator(git:Git) = {

    val logs = git.log.all.call()

    val logsIt = logs.asScala.toIterator

    def splitEmail(st:String) = {
      val fields = st.split('@')
      if (fields.size > 1) {
        (fields(0), fields(1))
      } else {
        (fields(0), "")
      }

    }

    logsIt.map { l =>
      val author = l.getAuthorIdent().getEmailAddress
      val committer = l.getCommitterIdent().getEmailAddress
      val aut = splitEmail(author)
      val com = splitEmail(committer)

      val authorName = l.getAuthorIdent().getName
      val committerName = l.getCommitterIdent().getName

      def dealWithSingleWords(key:String, addon: String)= {
        // we don't like names that don't have spaces
        // since they are usually reused (eg. Jim, root, etc)
        // so instead, use the other field
        val noacc = strip_accents(key)
        if (noacc.contains(' ')) 
          noacc.toLowerCase
        else (noacc+" at " +addon).toLowerCase
      }

      val authorKey = dealWithSingleWords(authorName, author)
      val commKey = dealWithSingleWords(committerName, committer)
      
      // tuple to return
      
      (
        new Person(authorName, authorKey, author, author.toLowerCase, aut._1,aut._2),
        new Person(committerName, commKey, committer, committer.toLowerCase, com._1, com._2)
      )

    }

  }

  def isBare(git:Git) : Boolean = {
    val storedConfig = git.getRepository.getConfig
    storedConfig.getBoolean("core", null, "bare", false)
  }

  def write_sheet(path:String,
    records: Map[String, List[Person]],
    keyStats: Map[String, Person_key],
    allCounts: Map[Person, Int],
    authorCounts: Map[Person, Int],
    commCounts: Map[Person, Int]) =  {

    def personRecordToRow(index:Int, key: String, p: Person) = {
      Row(index) {
        Set(
          StringCell(0,key),
          StringCell(1,p.name),
          StringCell(2,p.key),
          StringCell(3,p.email),
          StringCell(4,p.lcUserId),
          StringCell(5,p.lcDomain),
          NumericCell(6,allCounts(p).toDouble),
          NumericCell(7,authorCounts.getOrElse(p,0).toDouble),
          NumericCell(8,commCounts.getOrElse(p,0).toDouble)
        )
      }
    }

    def keyRecordToRow(index:Int, key: Person_key) = {
      Row(index) {
        Set(
          StringCell(0,key.key),
          StringCell(1,key.preferred),
          NumericCell(2,key.identCount.toDouble),
          NumericCell(3,key.allCount.toDouble),
          NumericCell(4,key.authoredCount.toDouble),
          NumericCell(5,key.committedCount.toDouble)
        )
      }
    }
    val headerStyle =
      Some(CellStyle(Font(bold = true),DataFormat("General")))

    val headerIdent =

      Set(
        Row(0) {
//        Set(
//          FormulaCell(6, s"=sum(G2..G${records.size})"))
        Set(
          StringCell(0,"key"),
          StringCell(1,"lcname"),
          StringCell(2,"name"),
          StringCell(3,"email"),
          StringCell(4,"lcUserId"),
          StringCell(5,"lcDomain"),
          StringCell(6,"countAll"),
          StringCell(7,"countAuthored"),
          StringCell(8,"countCommitted")
        )
      })

    val headerKeyStats =
      Set(Row(0) {
//        Set(
//          FormulaCell(6, s"=sum(G2..G${records.size})"))
        Set(
          StringCell(0,"key"),
          StringCell(1,"preferred"),
          StringCell(2,"identCount"),
          StringCell(3,"allCount"),
          StringCell(4,"authoredCount"),
          StringCell(5,"committedCount")
        )
      })


    val identRows = records.toSeq.sortBy{_._1}.
      foldLeft((Set[info.folone.scala.poi.Row](), 1)){ case((acc, offset), (key,person)) =>
      val newRows = person.zipWithIndex.map{case (p,i) =>
        personRecordToRow(i+offset, key, p)
      }
      (acc ++ newRows, offset + newRows.size)
    }._1

    val keyRows = keyStats.values.toList.sortBy(_.key).foldLeft((Set[info.folone.scala.poi.Row](), 1)){ case((acc, offset), stats) =>
      val newRow = keyRecordToRow(offset, stats)
      (acc + newRow, offset +  1)
    }._1


    val sheetOne = Workbook {
      Set(
        Sheet("identities") {
          headerIdent ++ identRows
        },
        Sheet("stats") {
          headerKeyStats ++ keyRows
        })
    }
    sheetOne.safeToFile(path).fold(ex ⇒ throw ex, identity).unsafePerformIO
  }




  def main(args: Array[String]) {
    
    if (args.size != 3) {
      println(s"Usage   <pathtorepo> <spredsheet> <dbName>")
      System.exit(1)
    }

    val repo = args(0)
    val sheetfile = args(1)
    val dbName = args(2)


    // this part is the biggest memory hog...
    // it loads each commit author and committer and creates a record
    // then converts it into an array
    // for optimization (if ever attempted):
    //   the toArray can probably be optimized with a foldleft to
    //   create the maps at the same time as it is traversed
    //   but not worth my time now. Linux (.7M commits) takes 5 minutes,
    //   I am OK with that

    println(s"Processing repo... [$repo] into spreadsheet [$sheetfile] and authors xdb [$dbName]")

    val fileRepo = new File(repo)

    val git = Git.open(fileRepo)
    val gitIter = git_commits_iterator(git).toArray
    val (authors,committers) = gitIter.unzip
    println(s"Loaded ${gitIter.size} commits...")

    // create a map with the counts of each

    val autMap = authors.groupBy(identity).mapValues(_.length)
    val commitMap = committers.groupBy(identity).mapValues(_.length)


    // combine them into a single set
    val everybody = autMap ++ commitMap.map{ case (k,v) => k -> (v + autMap.getOrElse(k,0)) }

    // unify by name
    println("Unifying by name...")

    val byName = everybody.groupBy(x => x._1.key)//.filter(x => x._2.exists(_._1.lcEmail.contains("dmg")))

    // drop the counts, we don't need them for this
    val setsNames = byName.map{_._2}.map{ m =>
      m.keys
    }
    println(s"  ... found ${setsNames.size} different person names")

    // see http://stackoverflow.com/questions/25616010/merge-sets-of-sets-that-contain-common-elements-in-scala
    // for performance improvements, but it is not worth it for our purpose
    // i believe the cost of traversing the log might be similar to this cost

    println("Unifying by email...")

    // unify by common email
    val unifiedByEmail = setsNames.foldLeft(Set.empty[Set[Person]])((cum, curi) => {
      val cur = curi.toSet
      val curEmails = cur.map{_.lcEmail}
      val (hasCommon, rest) = cum.partition(_.map{_.lcEmail} & curEmails nonEmpty)
      rest + (cur ++ hasCommon.flatten)
    })

    println(s"    ... reduced to ${unifiedByEmail.size} persons")


    // now turn the set of sets into a map using the key, and the rhs is a list ordered by importance
    // giving priority to the number of times the author has used that identify

    val mapByKey = unifiedByEmail.map { el:Set[Person] =>
      // get the most common key as the key to the map
      val key = el.map{x=>x.key}.toList.sortBy(x => -(byName(x).size)).take(1)
      //sort the records by total first, and if same, by number as author
      val records = el.toList.sortBy{x =>
        val all = everybody(x)
        val aut = autMap.getOrElse(x,0)
        (-all, -aut)
      }
      (key(0),records)
    }.toMap

    // we will use the most commonly used email as the preferred name
    // attach the count of all, authored, committed

    val keys = mapByKey.map{ case (k,v) =>
      val nameToUse = if (v(0).name.contains(" ")) v(0).name else v(0).email
      val identCount = v.size
      val countAll = v.map{ e =>
        (everybody(e),
          autMap.getOrElse(e,0),
          commitMap.getOrElse(e,0))
      }.foldLeft((0,0,0)){ case ((a1,a2,a3), (i1,i2,i3)) => (a1 +i1, a2+i2,a3+i3)}
      (k, new Person_key(k, nameToUse, identCount, countAll._1, countAll._2, countAll._3))
    }.toMap

        
    // WE ARE DONE
    // mapByKey contains a map from key to list of Persons
    // keys contains a map from key to person_key with details of each key

    // now output to spreedsheet 

    println("Writing the spreedsheet... $sheetfile")

    write_sheet(sheetfile, mapByKey, keys, everybody, autMap, commitMap)

    println("Replacing tables  in database... ${dbName}" )

    write_database(dbName, mapByKey, autMap, commitMap)

/*
    System.exit(0)


    mapByKey.foreach { case (key, li) =>
      print(key)
      print("->")
      print(keys(key))
      println
      li.foreach{item =>
        print("       ")
        print(everybody(item))
        print(" ")
        print(autMap.getOrElse(item,0))
        print(" ")
        print(commitMap.getOrElse(item,0))
        print(" ")
        print(item)
        println
      }
    }
 */


  }
}
