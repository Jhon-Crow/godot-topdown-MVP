title:	fix враги в состоянии Pursuming
state:	OPEN
author:	Jhon-Crow (Jhon-Crow)
labels:	
comments:	0
assignees:	
projects:	
milestone:	
number:	1814
--
<img width="805" height="454" alt="Image" src="https://github.com/user-attachments/assets/cb58640e-dc05-4d33-866d-592ab507b2c7" />

<img width="889" height="428" alt="Image" src="https://github.com/user-attachments/assets/11099c8a-6006-41bb-a3d2-892df4ab09d6" />

<img width="536" height="657" alt="Image" src="https://github.com/user-attachments/assets/72be91a7-64bf-4a35-9a14-dc98b6672531" />

враги должны быть в состоянии Flanking, но вместо этого они ходят туда сюда и не смогут добраться до игрока пока игрок не сделает хотя бы один выстрел

[game_log_20260411_164253.txt](https://github.com/user-attachments/files/26646369/game_log_20260411_164253.txt)

[game_log_20260411_164631.txt](https://github.com/user-attachments/files/26646389/game_log_20260411_164631.txt)

[game_log_20260411_170145.txt](https://github.com/user-attachments/files/26646498/game_log_20260411_170145.txt)

[game_log_20260413_211243.txt](https://github.com/user-attachments/files/26683940/game_log_20260413_211243.txt)

у врагов похоже вообще не включается состояние Flenking
проверь работают ли все существующие состояния врагов GOAP (сейчас точно работает переход в поиск, Pursuming, combat)

Please download all logs and data related about the issue to this repository, make sure we compile that data to `./docs/case-studies/issue-{id}` folder, and use it to do deep case study analysis (also make sure to search online for additional facts and data), in which we will reconstruct timeline/sequence of events, find root causes of the problem, and propose possible solutions.

