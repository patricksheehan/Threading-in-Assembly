// Patrick Sheehan

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

int main()
{
    int x [10] = {10,9,8,7,6,5,4,3,2,1};
    int n = 10;
    int nth = 4;
    
    ucdsort(x,n,nth);
    return 0;
}