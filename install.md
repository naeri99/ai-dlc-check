### install vscode web first 
- source ./vscode/install-code-server.sh
- 이후 http://{address}:8080 으로 접속하면 vscode web에 접속 가능 


### install docker and elasticsearch and postgresql
source ./workflow.sh
- docker안에 elasticsearch와 postgres 설치 


### project 생성
- mkdir ~/project


### kiro 파일 project로 이동
- cp -r {git위치}/kiro ~/project 


### kiro 파일이름 변경
- mv ~/project/kiro ~/project/.kiro


### project directory에서 kiro 실행
- cd ~/proejct && kiro-cli