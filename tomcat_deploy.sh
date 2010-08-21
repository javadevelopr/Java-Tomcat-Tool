#!/usr/bin/env bash

#Author: Sam Olof
#Date: 02-24-2009
#Desc:	Deploys Java web applications to a local or remote Apache Tomcat server
#	It takes all source and auxilliary file in a directory (should have a flat 
#	structure), creates a deployment descriptor file, compiles all Java class 
#	files, creates a WAR archive and deploys them to the local or remote server.
#	It will also organize all supporting files such as image, javascript and 
#	resource jars, updating the relative path references to them within your 
#	source code.
#
#	Tested on FreeBSD and Debian. Not tested extensively.

	

#Usage: ./tomcat_deploy [-g] [-t path/to/tomcat/root ] [path/to/files ] 
#	
#	-g or --graphical:	optional flag to run in graphical mode (requires zenity)
#	-t or --tomcat-home: 	use this flag to specify the path to the Tomcat Home 
#				directory. If the server is on a remote host precede the
#				path name with the hostname or ip address followed by a 
#				colon and the path i.e "<hostname>:<path>"
	

function do_jsp(){
        for f in `ls *.jsp 2>/dev/null`;do
	      servletname=$(basename $f| cut -d '.' -f1 )

              cat >>${DIRNAME}/WEB-INF/web.xml << EOF
		  <servlet>
		     <display-name>$servletname</display-name>	 
		     <servlet-name>$servletname</servlet-name>
		     <jsp-file>/${servletname}.jsp</jsp-file>
	          </servlet>
EOF

			cat >> $tmpfile << EOF
 		 <servlet-mapping>
		    <servlet-name>$servletname</servlet-name>
		    <url-pattern>/${servletname}</url-pattern>	
 		 </servlet-mapping>
EOF
      done
}

#Function updates the reference to script,image and css files in the
#html htm or jsp files, to their modified paths.
function update_refs {
  for file in `ls ${DIRNAME}/*.html ${DIRNAME}/*.htm ${DIRNAME}/*.jsp ${DIRNAME}/Stylesheets/*.css ${DIRNAME}/Scripts/*.js 2>/dev/null`; do	
   ex $file << EOF
    :%s/$1/\/${APPNAME}\/$2\/$1/g
    :wq 
EOF
done
}

function deploy_files {
  for f in `ls *.${1} 2>/dev/null`; do
    cp $f ${DIRNAME}/${2}
    #update references
    test $3 && update_refs $f $2 
  done
}


function foo(){
	#setup classpath
        if [ -f ${TOMCAT_HOME}/lib/servlet-api.jar ]; then   
             CLASSPATH="${TOMCAT_HOME}/lib/servlet-api.jar:$CLASSPATH"
        else
             CLASSPATH="${TOMCAT_HOME}/common/lib/servlet-api.jar:$CLASSPATH"
        fi

	#Use this to log compile errors
        comp_err_file=`mktemp /tmp/tomcat-deploy-tool_err.XXX` && chmod a+r $comp_err_file

	for f in `find $DIRPATH -maxdepth 1 -name "*.java"`;do 
		filename=$(basename $f)
	        javafilename=$(basename $f| cut -d '.' -f1 )
		

		#Handle packages		
		pkgname=`grep $f -o -e "package[[:space:]].*;[[:space:]]*$"`
		test -n "$pkgname" && pkgname=$(echo ${pkgname#*:} | tr -d ';' | awk '{print $2}')
		test -n "$pkgname" && servletclass="${pkgname}.${javafilename}" || servletclass="$javafilename"

		
 		urlpattern="${javafilename}"
		dr=${DIRNAME}/WEB-INF/classes


		if [ $GRAPHICAL ]; then
 		  javac -classpath $CLASSPATH -d $dr -nowarn $f 2>$comp_err_file | zenity --progress --auto-close --text="Compiling $f"
		  if [ ! $? -ne 0 ]; then 
			zenity --question --text="Unable to compile $filename. Exiting with Errors. View compile errors?" --ok-label="Yes"
                        if [ $? -eq 0 ]; then zenity --text-info --filename="$comp_err_file";fi  
                        exit 1
                  fi
		else
			echo "Compiling $f ..."
			javac -classpath $CLASSPATH -d $dr -nowarn $f 2>$comp_err_file 						
			if [ $? -ne 0 ]; then 
				echo "Unable to compile $filename. Exiting with Errors. See $comp_err_file for compile errors."
				exit 1
			fi
                        echo "Compiled"
		fi			
		
		#Add description to web.xml descriptor if class is a servlet
		grep $f -q -e "^[[:space:]]*[pcf].*lass.*extends[[:space:]]*HttpServlet"
		
		if [ $? -eq 0 ]; then
			cat >>${DIRNAME}/WEB-INF/web.xml << EOF
		  <servlet>
		     <servlet-name>$javafilename</servlet-name>
		     <display-name>$javafilename</display-name>	 
                     <description>Generated with tomcat_deploy_tool.sh</description>
		     <servlet-class>$servletclass</servlet-class>
	          </servlet>
EOF

			cat >> $tmpfile << EOF
 		 <servlet-mapping>
		    <servlet-name>$javafilename</servlet-name>
		    <url-pattern>/${urlpattern}</url-pattern>	
 		 </servlet-mapping>
EOF
     		fi		
	done
}

################ START HERE ######################
#parse command line args

for ((i=0; i <= $#; i++));do
  eval arg='$'$i
  case $arg in
	"-g"|"--graphical") GRAPHICAL=true ;;
	"-t"|"--tomcat-home")
	    eval CATALINA_HOME='$'$((i+1))	    
	;;
	*)
	    eval y='$'$((i-1))	
	    if [ $i -eq $# -a $i -gt 0 -a $y != "-t" ]; then
		if [ -d $arg ]; then DIRPATH=$arg ; fi
	    fi
        ;;
  esac
done	 		


if [ $GRAPHICAL ]; then
        #DISPNAME=`zenity --entry --text="Choose a name for your application" --title="Tomcat Deployer"`
        #if [ $? -ne 0 ];then exit 0 ; fi

        if [ ! $DIRPATH ]; then
          zenity --info --text='Click <b>OK</b> to select the directory with your files and 
your Tomcat installation directory 
(If the <i>$CATALINA_HOME</i> environment variable is not set).'

          DIRPATH=`zenity --file-selection --directory --title="Select directory"`
        fi  
	if [ -z $DIRPATH ];then exit 0 ; fi

	if [ $CATALINA_HOME ];then
	  TOMCAT_HOME="${CATALINA_HOME}"
	else
	  TOMCAT_HOME=`zenity --file-selection --directory --title="Select Apache Tomcat home directory"`
	fi

	if [ -z $TOMCAT_HOME ];then exit 0 ; fi

        zenity --question --text="Is your <b>/webapps</b> directory in the Tomcat home directory? 
Click <b>No</b> to select a different location." --ok-label="Yes" --cancel-label="No"
        if [ $? -ne 0 ]; then 
          WEBAPPS_HOME=`zenity --file-selection --directory --title="Select /webapps directory"`
        else
          WEBAPPS_HOME=$TOMCAT_HOME/webapps
        fi  

else
        #echo "Choose a Name for your application:"
        #read DISPNAME
        if [ ! $DIRPATH ]; then
          echo "Enter the full path to the directory containing your files 
(without "/" at the end):"
          read DIRPATH
	fi	
	if [ $CATALINA_HOME ]; then 
		TOMCAT_HOME=$CATALINA_HOME
	else
		echo "Enter the path to the Tomcat home directory
(without "/" at the end):"
		read TOMCAT_HOME
	fi
        
        echo "Enter the full path to your /webapps directory 
if its not in the Tomcat home directory:"
        read WEBAPPS_HOME
        if [ ! $WEBAPPS_HOME ]; then WEBAPPS_HOME=${TOMCAT_HOME}/webapps ; fi
fi

#determine if TOMCAT_HOME is in remote location 
test $TOMCAT_HOME && REMOTE=${TOMCAT_HOME%:*} && [ $REMOTE != $TOMCAT_HOME ] || unset REMOTE 
[ "$REMOTE" ] && TOMCAT_HOME=${TOMCAT_HOME#*:}
[ "$REMOTE" ] && WEBAPPS_HOME=${WEBAPPS_HOME#*:}

#open remote session if so
if [ "$REMOTE" ];then
	ssh $REMOTE -M -S /tmp/%r@%h:%p -N -f	
	REMOTE_CALL="ssh -X $REMOTE -S /tmp/%r@%h:%p -N -f"
        RPATH="/tmp/%r@%h:%p"
else
	REMOTE_CALL=""
fi



set -e #Ensure we exit if any of the ff fail

#Create temporary directory to assemble files and tmpfile
tmpfile=`mktemp /tmp/tomcatdeploy.XXX`
cd $DIRPATH && DIRPATH=$PWD #latter just in case user entered relative path
APPNAME=`basename $PWD`
DISPNAME=$APPNAME
#APPNAME=$DISPNAME
DIRNAME=`mktemp -d /tmp/${APPNAME}XXXX`

#Create structure
mkdir ${DIRNAME}/WEB-INF && mkdir ${DIRNAME}/WEB-INF/classes
mkdir ${DIRNAME}/Stylesheets
mkdir ${DIRNAME}/Images
mkdir ${DIRNAME}/Scripts
mkdir ${DIRNAME}/WEB-INF/lib
set +e


deploy_files html ; deploy_files jsp ; deploy_files htm 
deploy_files js Scripts 1
deploy_files css Stylesheets 1
deploy_files svg Images 1; deploy_files ico Images 1; deploy_files gif Images 1
deploy_files jpeg Images 1; deploy_files jpg Images 1; deploy_files png Images 1
deploy_files jspf WEB-INF 1
deploy_files jar WEB-INF/lib


#Create deployment-descriptor file, web.xml
cat > ${DIRNAME}/WEB-INF/web.xml << EOF
<?xml version="1.0" encoding="ISO-8859-1"?>
<!DOCTYPE web-app
  PUBLIC "-//Sun Microsystems, Inc.//DTD Web Application 2.3//EN"
  "http://java.sun.com/dtd/web-app_2_3.dtd">

<web-app> 
  <display-name>$DISPNAME</display-name>  
  <description>$DISPNAME</description>
EOF
foo
do_jsp

cat $tmpfile >> ${DIRNAME}/WEB-INF/web.xml

cat >> ${DIRNAME}/WEB-INF/web.xml << EOF
  <welcome-file-list>
	<welcome-file>index.html</welcome-file>
	<welcome-file>index.htm</welcome-file>
	<welcome-file>index.jsp</welcome-file>
  </welcome-file-list>
</web-app>
EOF

if [ $GRAPHICAL ]; then zenity --question --text="A deployment descriptor web.xml has
been created. Would you like to edit it?" --ok-label="Yes" --cancel-label="No"
  if [ $? -eq 0 ]; then gedit ${DIRNAME}/WEB-INF/web.xml ; fi
fi
 

#Create war archive, deploy app 
cd $DIRNAME

#No need to restart tomcat if context is reloadable
$REMOTE_CALL cat $TOMCAT_HOME/conf/context.xml | egrep -e "<Context .*reloadable=\"[T|t]rue\"" >/dev/null \
&& test $? -eq 0 && NO_RESTART=true


#Find tomcat init script if we have to restart and make sure user has necessary file permission on script
#Get GID to check if user has access to init scripts
GID=$($REMOTE_CALL id -g)


TOMCAT_VERSION=$($REMOTE_CALL ${TOMCAT_HOME}/bin/version.sh | egrep -o "tomcat[[:digit:]]*\.?[[:digit:]]*" \
| head -1 | egrep -o [0-9][0-9]*\.?[0-9]*)

initdirs=("/etc/rc.d/init.d" "/etc/init.d" "/etc/rc.d")
initscripts=("tomcat${TOMCAT_VERSION}" "tomcat-${TOMCAT_VERSION}" "tomcat_${TOMCAT_VERSION}" "tomcat")

#a little helper function
function get_init_script {
  for (( i=0; i < ${#initscripts[@]}; i++ ));do
    sf=${initscripts[$i]}
    $REMOTE_CALL test -x ${1}/${sf} && INITSCRIPT=${1}/${sf} && break
  done
}

for (( k=0; k < ${#initdirs[@]}; k++ ));do
  dd=${initdirs[$k]}
  test -d $dd && [ $GID -eq 0 ] && get_init_script $dd && break
done


#If can't find init scripts use scripts in $TOMCAT_HOME. Requires setting JAVA_HOME or JRE_HOME
txt="\$JAVA_HOME does not appear to have been set. 
I require this to restart Tomcat"
if [ ! "$INITSCRIPT" -o ! "$NO_RESTART" ]; then 
  [ "$REMOTE" ] && JAVA_HOME=`$REMOTE_CALL env| grep JAVA_HOME` #this doesn't really work	
  if [ ! $JAVA_HOME -o ! $JRE_HOME ];then
    if [ $GRAPHICAL ]; then
      zenity --question --text="${txt}. Click OK to select the root directory for your java runtime environment. (If deploying to remote host, use path relative to root of remote host):" 
      if [ $? -eq 0 ]; then
        $REMOTE_CALL export JAVA_HOME=`zenity --file-selection --directory --title="Select \$JAVA_HOME"`
      fi
    else
      echo "${txt}. Enter path to root directory for your java runtime environment"
      echo "(If deploying to remote host, use path relative to root of remote host):"	
      read JAVA_HOME
      [ $JAVA_HOME ] && $REMOTE_CALL export JAVA_HOME=$JAVA_HOME
    fi
  fi
  $REMOTE_CALL ${TOMCAT_HOME}/bin/catalina.sh stop 2>/dev/null
  jar cf ${APPNAME}.war *
  
  #try to remove previous versions
  set -e
  trap "echo 'You do not have the permissions to complete the deployment. 
Try running this as root'; exit 1" EXIT
  $REMOTE_CALL rm -rf ${WEBAPPS_HOME}/${APPNAME} ${WEBAPPS_HOME}/${APPNAME}.war 2>/dev/null

  [ $REMOTE ] && scp -o 'ControlPath /tmp/%r@%h:%p' ${APPNAME}.war $REMOTE:${WEBAPPS_HOME}/${APPNAME}.war || \
	mv ${APPNAME}.war ${WEBAPPS_HOME} 2>/dev/null
  set +e

  $REMOTE_CALL ${TOMCAT_HOME}/bin/catalina.sh start  
  #unset trap for exit
  trap - EXIT

else
  #Move war file and restart tomcat server  
  [ ! $NO_RESTART ]&& $REMOTE_CALL ${INITSCRIPT} stop 
  jar cf ${APPNAME}.war *
  
  #try to remove previous versions
  $REMOTE_CALL rm -rf ${WEBAPPS_HOME}/${APPNAME} ${WEBAPPS_HOME}/${APPNAME}.war 
  
  [ "$REMOTE" ] && scp -o 'ControlPath /tmp/%r@%h:%p' ${APPNAME}.war $REMOTE:${WEBAPPS_HOME} || \
	mv ${APPNAME}.war ${WEBAPPS_HOME} 2>/dev/null
  
  [ ! $NO_RESTART ] && $REMOTE_CALL ${INITSCRIPT} start 
fi

#Cleanup

if [ $GRAPHICAL ]; then
  zenity --question --text="Deployment complete. Keep a local copy of the deployment directory?." --ok-label="Yes" --cancel-label="No"
  if [ $? -eq 0 ]; then
    mkdir $DIRPATH/$APPNAME
    cp -R $DIRNAME/* $DIRPATH/$APPNAME/
  fi
else
   echo "Deployment complete. Keep a local copy of the deployment directory?(y/n):"
  while [ ! $satis ];do
    read -n 1 -s resp
    case $resp in
      y|Y)
        mkdir $DIRPATH/$APPNAME
        cp -R $DIRNAME/* $DIRPATH/$APPNAME/
        satis=true
        echo
        ;;
      n|N)
        satis=true
        echo
        ;;
      *) 
        echo "Please answer y/n"
        echo
        ;;
    esac
  done
fi

cd ../
rm -rf $DIRNAME
exit 0


