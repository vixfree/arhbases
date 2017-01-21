#!/bin/bash
## It is a system script for 1c database backups 
## author (c) by koshuba v.o. - open technologies
## licence MIT 2016
export LANG=ru_RU.UTF-8
## 
option=$1
rdate=$(date +%c);
arh_date=$(date +%d_%m_%y);
log_arh="/var/log/syslog";

## values read devices & index array values
host_smb="10.10.10.4";                                    #: хост подключения
login_smb=( '"Администратор" "mypass"' );                 #: логин и пароль к ресурсу
name_db=( "Base1" "Base2" "Base3" "Base4" );              #: имена каталогов баз данных
name_arh=( "base1_" "base2_" "base3_" "base4_" );         #: имена суточных архивов + дата на момент архивации
path_mnt="/mnt/read_smb";                                 #: директория для монтирования ресурса
path_main_arh="/arhbase";                                 #: основной каталог архивов
path_arh=( "day" "week" "month" );                        #: отдельные каталоги суточных, недельных и месячных архивов
path_tmp="/home/temp";                                    #: временная папка для архивации баз
path_in_cd=( "" );                                        #: путь входа для копирования
policy=( "user:sambashare" )                              #: права на архивы


## values for db arhives
read_smb=( "E$"  "$F");       #: ресурс где находятся базы данных - индексы ниже привязаны к нему
## <>
link_db=( '"0" "1"'  '"2" "3"' );                         #: индексы имен каталогов с базами
link_arh=( '"0" "1"'  '"2" "3"' );                        #: индексы имен архивов для сжатия
link_policy=( '"0" "0"'  '"0" "0"' )                      #: индексы права на архивы
link_in_cd=( '"0" "0"'  '"0" "0"' )                       #: индексы входа в каталог баз
link_login_smb=( '"0" "0"'  '"0" "0"' );                  #: индексы логин и пароль к ресурсу                                          
                                                                                                                                                             
## tmp                                                                                                                                                       
tmp_smb="";                                               #: текущий share для чтения                        
tmp_db=();                                                #: текущий список каталогов баз                  
tmp_login=();                                             #: текущий логин к ресурсу                           
tmp_nmdb=();                                              #: текущий список имен архивов                 
tmp_pl=();                                                #: текущие политики                                      
tmp_in_cd=();                                             #: текущий каталог входа к базам                                             
                                                                                                                                                             
## defaults                                                                                                                                                 
reports=();                                               #: массив для сообщений                               
event_type="";                       #: тип события для выполнения операции, за день, за неделю и.т.д.            
                                                                                                                                                             
## functions & operations                                                                                                                                    
## develop mode ...                                                                                                                                          
operation_day=( "checkLock" "mountSmb" "arhDb" "umountSmb" "lockOff" );                                        
operation_week=( "checkLock" "mountSmb" "arhDb" "umountSmb" "clearArh" "lockOff" );                    
operation_month=( "checkLock" "mountSmb" "arhDb" "umountSmb" "clearArh" "lockOff" );                   
operation_help=( "printInfo" );                                                                                                                    
execute_func=();                                                                                                                                             
## logic executor values
iFs=();
logic=();
value_in="";
lEnd=1;

##..............................................................................
## -@F logic executor
function eXlogic() {
lEnd=1;
if [[ ${#iFs[@]} -eq 0 ]]||[[ ${#iFs[@]} != ${#logic[@]} ]]
    then echo "exit";
         exit 0;
fi

local exfunc=();
for ((lg_index=0; lg_index != ${#iFs[@]}; lg_index++))
 do
    ## !! debug operation...
    ## echo "eXlogic = execution: function ${iFs[$lg_index]} : index=$lg_index";
    local lg=$(echo $((${iFs[$lg_index]})) );
    local exfunc=( ${logic[$lg_index]} );
    local runfunc=$(echo ${exfunc[$lg]}| sed 's/\"//g');
    $runfunc;
    if [[ $lEnd == 0 ]] 
        then lg_index=$((${#iFs[@]}-1)); 
    fi
done
iFs=();
logic=();
value_in="";
}

##..............................................................................
## -@F function check lock file
function checkLock() {
if [ ! -f /tmp/run-arh.lok ]
    then 
        echo >/tmp/run-arh.lok;
    else
        reports=();
        reports[${#reports[@]}]="обнаружен признак занятости, архивация баз по событию < $event_type > - не выполнена!";
        makeErr;
fi

}

##..............................................................................
## -@F function check lock file
function lockOff() {
rm -f /tmp/run-arh.lok;
reports=();
reports[${#reports[@]}]="архивация баз по событию < $event_type > - выполнена успешно."
writeToLog;
}

##.............................................................................
## -@F function mount share
function mountSmb(){

if [ ! -d $path_mnt ]
    then
        mkdir -p $path_mnt;
fi

this_login=( ${login_smb[$(echo ${tmp_login[0]}| sed 's/\"//g')]} );
## проверка на смонтированный ресурс, если есть - выход с ошибкой!
        test_mount=$(df -h|grep $host_smb|wc -m);

        if [ $test_mount != 0 ]
            then
                reports=();
                reports[${#reports[@]}]="обнаружен примонтированный ресурс, архивация баз по событию < $event_type > - не выполнена!";
                makeErr;
            else
            mount -t cifs //$host_smb/$tmp_smb $path_mnt -o gid=1000,uid=1000,file_mode=0666,dir_mode=0777,user=$(echo ${this_login[0]}| sed 's/\"//g'),pass=$(echo ${this_login[1]}| sed 's/\"//g');
        fi
} 

##.............................................................................
## -@F function umount share
function umountSmb(){
## проверка на смонтированный ресурс, если есть - откючаем...
        test_mount=$(df -h|grep $host_smb|wc -m);
        if [ $test_mount = 0 ]
            then
                reports=();
                reports[${#reports[@]}]=" не обнаружен примонтированный ресурс, по событию < $event_type > - прекращена!";
                makeErr;
            else
            umount $path_mnt;
        fi
}

##................................................................................
## -@F function copy end archive bases
function arhDb(){

local path_arh_in="";

iFs=(   "$(echo -n $event_type|sed 's/day//g'|wc -m) == 0"
        "$(echo -n $event_type|sed 's/week//g'|wc -m) == 0"
        "$(echo -n $event_type|sed 's/month//g'|wc -m) == 0" );

logic=( '"" "arhDay"'
        '"" "arhWeek"'
        '"errArh" "arhMonth"'
        );

    function arhDay() {
    lEnd=0;
    path_arh_in=$path_main_arh/${path_arh[0]};
    makeArh;
    }

    function arhWeek() {
    lEnd=0;
    path_arh_in=$path_main_arh/${path_arh[1]};
    makeArh;
    }

    function arhMonth(){
    lEnd=0;
    path_arh_in=$path_main_arh/${path_arh[2]};
    makeArh;
    }


    function makeArh() {
##
    for ((index_make=0; index_make != ${#tmp_db[@]}; index_make++))
        do
    # текущий каталог входа к базам
    local in_cd="${path_in_cd[$(echo ${tmp_in_cd[$index_make]}| sed 's/\"//g')]}";

    # получаем имя базы для копирования
    local in_db="${name_db[$(echo ${tmp_db[$index_make]}| sed 's/\"//g')]}";
    # копируем данную базу во временный каталог
    if [ ! -d $path_tmp ]
        then
        mkdir -p $path_tmp
        chmod -R 0666 $path_tmp;
        chmod -R ugo+X $path_tmp;
    fi
    if [ ! -d $path_tmp/$in_db ]
        then
        mkdir -p $path_tmp/$in_db
        chmod -R 0666 $path_tmp/$in_db;
        chmod -R ugo+X $path_tmp/$in_db;
    fi
    cd $path_mnt/$in_cd;
    ##cp -f -R $in_db $path_tmp;
    ## исключаем блокированные файлы базы 1с
    find $in_db -type 'f' | grep -v .cfl|grep -v .cgr| xargs -n 1 -I % cp -f -R --parents  "%" $path_tmp;
    cd
    #............................................
    # получаем имя архива для данной базы
    local arh_dbname="$path_arh_in/${name_arh[$(echo ${tmp_nmdb[$index_make]}| sed 's/\"//g')]}$arh_date.7z";
    if [ ! -d $path_arh_in ]
        then
        mkdir -p $path_arh_in;
        chmod -R 0666 $path_arh_in;
        chmod -R ugo+X $path_arh_in;
    fi
    # архивируем базу в заданный каталог..
    cd $path_tmp && 7z -t7z -mx=9 -r -ssc a $arh_dbname $in_db $2>/dev/null;
    cd
    # устанавливаем права на базы
    chown -R ${policy[$(echo ${tmp_pl[$index_make]}| sed 's/\"//g')]} $arh_dbname ;
    #............................................
    # удаляем временную копию текущей базы
    rm -f -R $path_tmp/$in_db;
    #............................................
    done
    }

    function errArh(){
    lEnd=0;
    reports=();
    reports[${#reports[@]}]="архивация по событию < $event_type > не выполнена...";
    printInfo;
    }

eXlogic;
}

##................................................................................
function clearArh() {
local path_arh_clr="";

iFs=(   "$(echo -n $event_type|sed 's/week//g'|wc -m) == 0"
        "$(echo -n $event_type|sed 's/month//g'|wc -m) == 0" );

logic=( '"" "clearDay"'
        '"errClear" "clearWeek"'
        );

    function clearDay() {
    lEnd=0;
    path_arh_clr=$path_main_arh/${path_arh[0]};
    clrOldDb;
    # удаляем архивы по имени +маска
    }

    function clearWeek() {
    lEnd=0;
    path_arh_clr=$path_main_arh/${path_arh[0]};
    clrOldDb;
    path_arh_clr=$path_main_arh/${path_arh[1]};
    clrOldDb;
    # удаляем архивы по имени +маска
    }

    function errClear(){
    lEnd=0;
    reports=();
    reports[${#reports[@]}]="удаление по событию < $event_type > не выполнено...";
    writeToLog;
    printInfo;
    # обработка ошибок если есть...
    }

function clrOldDb() {
for ((index_clr=0; index_clr != ${#tmp_db[@]}; index_clr++))
        do
    # получаем имя базы для удаления
    local clr_db="${name_arh[$(echo ${tmp_db[$index_clr]}| sed 's/\"//g')]}";
    rm -f $path_arh_clr/$clr_db*;
done
}

eXlogic;
}


##................................................................................
##--@F make all errors
function makeErr() {
        reports[${#reports[@]}]="операция по событию < $event_type > не выполнена!";
 printInfo;
 writeToLog;
 exit 0;
 exit 1;
}

##................................................................................
##--@F make all messages
function printInfo() {
value_in="$option";
iFs=(   "$(echo -n $value_in|wc -m) == 0"
        "$(echo -n $value_in|sed 's/--help//g'|wc -m) == 0" 
        "$(echo -n ${#reports[@]}) == 0" );

logic=( '"" "pInone"'
        '"" "pIhelp"'
        '"pIdf" "pInone"' );


function pInone() {
    lEnd=0;
    clear
    echo
    ##echo "psec:$(($(date +%s%3N)-$settime))";
    exit 0;
}

function pIhelp() {
    lEnd=0;
    clear
    reports=();
    reports[${#reports[@]}]="Архивация за один день: --d"; 
    reports[${#reports[@]}]="Архивация на конец недели (удалаются все архивы за день и содается архив на конец недели): --w";
    reports[${#reports[@]}]="Архивация на конец месяца (удалаются все архивы за день и за неделю затем содается архив на конец месяца): --m";
    pIdf;
    exit 0;
}

## default function last eXlogic..
function pIdf() {
    for ((rpt_index=0; rpt_index != ${#reports[@]}; rpt_index++))
        do
    echo   "${reports[$rpt_index]}";
    done
    exit 0;
    }
eXlogic;
}

##................................................................................
##--@F make all messages to log file
function writeToLog() {
for ((wrl_index=0; wrl_index != ${#reports[@]}; wrl_index++))
        do
    echo "$rdate - arh_db_zraid: ${reports[$wrl_index]}" >> $log_arh;
done
}

##................................................................................
##--@F executor
## обработчик операций..
function executor() {

if [[ ${#execute_func[@]} -eq 0 ]] 
    then echo "exit";
         exit 0; 
fi
for ((ex_index=0; ex_index != ${#execute_func[@]}; ex_index++))
 do
    ## !! debug operation...
    ## echo "execution: function ${execute_func[ex_index]}"
 ${execute_func[ex_index]};
done
}

##................................................................................
## обработка вызовов операций в зависимости от количества указанных ресурсов для чтения баз
function agent() {
for ((step_i=0; step_i != ${#read_smb[@]}; step_i++))
 do
tmp_smb=${read_smb[$step_i]};
tmp_db=( ${link_db[$step_i]} );
tmp_nmdb=( ${link_arh[$step_i]} );
tmp_pl=( ${link_policy[$step_i]} );
tmp_in_cd=( ${link_in_cd[$step_i]} );
tmp_login=( ${link_login_smb[$step_i]} );
executor
done
}


## events
case "$option" in

## the arhive day bases
"--d" | "--d" )
testday=$(date +%d|grep 01|wc -m);
    if [ "$testday" != 0 ]
        then
        event_type="month";
        execute_func=( ${operation_month[@]} );
        agent;
    #иначе делаем ежедневный архив
        else
        event_type="day";
        execute_func=( ${operation_day[@]} );
        agent;
    fi
exit 0
;;

## the arhive week bases
"--w" | "--w" )
testday=$(date +%d|grep 01|wc -m);
    if [ "$testday" != 0 ]
        then
        event_type="month";
        execute_func=( ${operation_month[@]} );
        agent;
    #иначе делаем еженедельный архив
        else
        event_type="week";
        execute_func=( ${operation_week[@]} );
        agent;
    fi
exit 0
;;

## the arhive month bases
"--m" | "--m" )
event_type="month";
execute_func=( ${operation_month[@]} );
agent;
exit 0
;;

## help
"--help" | "--help" )
execute_func=( ${operation_help[@]} );
executor
exit 0
;;

* )
# selecting defaults.
option="--help";
execute_func=( ${operation_help[@]} );
executor
exit 1
;;
esac
