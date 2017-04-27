import com.github.retronym.SbtOneJar._

oneJarSettings


libraryDependencies ++= Seq(
  "com.typesafe.slick" %% "slick" % "3.0.0",
  "org.xerial" % "sqlite-jdbc" % "3.8.0-SNAPSHOT",
  "com.zaxxer" % "HikariCP" % "2.4.1",
  "org.eclipse.jgit" % "org.eclipse.jgit" % "4.6.0.201612231935-r"
)

resolvers ++= Seq(
  "SQLite-JDBC Repository" at "https://oss.sonatype.org/content/repositories/snapshots",
  "jgit-repo" at "http://download.eclipse.org/jgit/maven"
)

