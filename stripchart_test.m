x = 1:1000;
y = sin(2*pi*x/1000);
hLine = plot(x,y);
stripchart('Initialize',gca)
for i=1:1000
	stripchart('Update',hLine,y(i))
end
